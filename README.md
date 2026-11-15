# Horizon iOS 一条龙（方案 B：瘦 ipa + 首启导入资源）

把 [horizon-rust/horizon](https://github.com/horizon-rust/horizon)（Rust 重写的 Minecraft Java 版）
跑在 iPhone / iPad 上。ipa 里**不带** Mojang 的资源，首次启动由玩家导入自己那份 `assets/` + `data/`。

工具清单先看 [TOOLS.md](TOOLS.md)。

---

## 已经做完并验证过的部分

| 项 | 状态 |
|---|---|
| `crates/horizon-ios-shell` 在 `aarch64-apple-ios` 上编译 | ✅ `cargo check --release` 通过，wgpu 30.0.2 / metal 后端，0 error 0 warning |
| wgpu 30 的实际 API 适配（`CurrentSurfaceTexture`、`Queue::present`、`get_default_config`、`immediate_size`、`multiview_mask`） | ✅ 按 crates.io 上 wgpu 30.0.2 源码逐个核对 |
| `CAMetalLayer → wgpu::SurfaceTargetUnsafe::CoreAnimationLayer` 通路 | ✅ 类型检查通过 |
| Info.plist（ProMotion、Metal 必需、局域网、文件共享） | ✅ 已用 `plistlib` 解析校验 |
| ipa 打包路径（`Payload/Horizon.app` → zip → 回读校验） | ✅ `make preview` 产出了 `build/Horizon-structure-preview.ipa` |
| Swift / Xcode 工程编译 | ⛔ 需要 macOS 或 CI（见下） |

`build/Horizon-structure-preview.ipa` 是**布局预览**，里面没有 Mach-O，装不上；它存在是为了证明
Info.plist 替换、bundle 结构和打包脚本都是对的，别把时间浪费在「上 CI 才发现打不出包」。

---

## 一条龙：出真 ipa

### 路线 0：一键脚本（建仓库 → 推 → 等构建 → 下载 ipa）

```bash
python one_click.py            # 公开仓库（macOS 分钟免费无限）
python one_click.py --private  # 私有仓库（macOS 分钟按 10 倍计费）
python one_click.py --build-only   # 仓库已推过，只重跑一次构建并下载
python one_click.py --dry-run      # 只看本地会提交什么，不联网
```

令牌从 `$GITHUB_TOKEN` / `$GH_TOKEN` / `gh auth token` 里取，都没有就交互输入（不回显、不落盘，
也不写进 `.git/config`）。脚本只用标准库：建仓库 → 设提交身份（用 API 拿不到名字时退回
`<id>+<login>@users.noreply.github.com`）→ 提交 → push → 轮询 Actions → 下载并解到 `dist/`。

### 路线 1：GitHub Actions（手动）

```bash
# 1. 把这个目录推成一个仓库（或直接 fork 进你已有的 Horizon fork 的 ios/ 下）
git init && git add . && git commit -m "horizon ios shell"
git remote add origin git@github.com:<you>/horizon-ios.git && git push -u origin main
```

推完 Actions 自动跑，8–12 分钟后在 **Actions → ios-ipa → Artifacts** 下拿 `Horizon-ipa`。
里面是 `Horizon-unsigned.ipa`。

### 路线 2：本机 macOS

```bash
brew install xcodegen
rustup target add aarch64-apple-ios
bash scripts/build_ipa.sh
# → build/Horizon-unsigned.ipa
```

### 路线 3：接进 Horizon 仓库本体（上游路线）

```bash
git clone --depth 1 https://github.com/horizon-rust/horizon ~/src/horizon
cp -R crates/horizon-ios-shell ~/src/horizon/crates/
cp -R ios ~/src/horizon/
cp -R scripts ~/src/horizon/
```

然后在 `~/src/horizon/Cargo.toml` 的 `[workspace] members` 里加 `"crates/horizon-ios-shell"`，
删掉本目录自己的 `Cargo.toml`（那是给独立编译用的 workspace 壳），
`cp project.yml ~/src/horizon/`，再 `bash scripts/build_ipa.sh`。
这样 `horizon-ios-shell` 直接复用 workspace 里的 `wgpu` 版本，不会出现两份 wgpu 链接冲突。

---

## 装进手机

未签名 ipa 三条路（详见 [TOOLS.md](TOOLS.md) 第 4 节）：

1. **Sideloadly**（Windows 就行）：拖 ipa 进去，填 Apple ID，7 天有效。
2. **付费开发者账号**：`scripts/resign_ipa.sh` 用 Ad Hoc 描述文件重签，1 年有效。
3. **TrollStore**：iOS 14.0–16.6.1 / 17.0 且机型在支持列表，装上就是永久。

装完第一次打开会看到导入页 —— 因为包里没有资源。下一步就是给它资源。

---

## 资源从哪来（方案 B 的关键）

```bash
# macOS / Linux
HORIZON_REPO=~/src/horizon bash scripts/prepare_assets.sh ~/Downloads/server.jar
# Windows
$env:HORIZON_REPO="C:\src\horizon"; .\scripts\prepare_assets.ps1 -ServerJar "$HOME\Downloads\server.jar"
```

产出 `horizon-assets.zip`（通常 300–700MB，不含音频时更小），然后：

- **数据线**：iMazing / Finder → App 文件共享 → 拖进 Horizon
- **隔空投送**：AirDrop 到手机 → 「文件」App 长按 → 共享 → Horizon
- **越狱**：`scp` 到沙盒 `Documents/`

打开 Horizon → 「导入 zip」→ 等进度 → 「开始游戏」。

> 这里没有任何下载行为：`horizon-prepare` 读的是**你自己那份** 26.3 的 `server.jar`，
> Horizon 在任何平台都不分发 Mojang 的文件。你要装到自己手机上，用的就是自己的那份数据。

---

## 现在屏幕上会看到什么

一个深色背景 + 一个绿色三角形，帧率在 Xcode 的 GPU 计里能看到，`hz_frame_count()` 还在涨。
这就是「Metal 通路成立」的全部证据。

真游戏要接进来，看 [crates/horizon-ios-shell/ATTACHING.md](crates/horizon-ios-shell/ATTACHING.md)：
拆 entry、注入 surface、触摸映射到 `Action`、资源根注入、以及 iOS 上按咬人顺序排的六个坑
（jetsam / unsafe 纪律 / 后台挂起 / 热量 / 音频 / 在线登录）。

## 目录

```
crates/horizon-ios-shell/   Rust：CAMetalLayer surface + 帧泵 + 触摸 + 资源根（已编译验证）
  ATTACHING.md              怎么换成真游戏
ios/Horizon/                Swift：UIWindow、GameView、CADisplayLink、导入页、ZipArchive
project.yml                 XcodeGen 工程定义（静态库路径、bridging header、链接参数）
scripts/                    build_ipa.sh / prepare_assets.* / resign_ipa.sh / make_skeleton_ipa.py
.github/workflows/          macos-15 上出 ipa，可选签名
```
