# 工具清单（方案 B：小 ipa + 首次启动导入资源包）

先看这张表，再看 [README.md](README.md) 的一条龙命令。

## 1. Windows 侧（你现在这台机器）

| 工具 | 版本 | 用途 | 装法 |
|---|---|---|---|
| Rust (rustup) | stable ≥ 1.85 | 给 `horizon-ios-shell` 做 `cargo check --target aarch64-apple-ios`，不需要链接器 | https://win.rustup.rs/x86_64 |
| aarch64-apple-ios target | — | 交叉检查 iOS 目标 | `rustup target add aarch64-apple-ios` |
| Python | ≥ 3.11 | `horizon-prepare` 的依赖；本仓库的 `make_skeleton_ipa.py` 也用它 | python.org |
| **JDK 25** | 25 | `horizon-prepare` 读你自备的 26.3 `server.jar`，**必须 25** | https://adoptium.net/temurin/releases/?version=25 |
| Git | 任意 | clone Horizon 仓库 | git-scm.com |
| zsign | 最新 | 可选，在 Windows 上给 ipa 重签/adhoc 签 | https://github.com/zhlynn/zsign (releases) |
| Sideloadly | 最新 | 可选，用 Apple ID 签 7 天证书并装进手机 | sideloadly.io |

## 2. macOS 侧（真机编译 ipa 必须，或用第 3 节的 CI 代替）

| 工具 | 版本 | 用途 |
|---|---|---|
| Xcode | 16.x 或更高 | iPhoneOS SDK、`xcodebuild`、`codesign`、Metal 调试 |
| Xcode Command Line Tools | 随 Xcode | `xcrun`、`ld`、`actool` |
| XcodeGen | ≥ 2.40 | 用 `project.yml` 生成 `.xcodeproj`（`brew install xcodegen`） |
| Rust + `aarch64-apple-ios` | stable | 编 `libhorizon_ios_shell.a` |
| `cargo-binstall`（可选） | 最新 | 装 `cargo-horizon-mod` 等 |

> 只用 Xcode 也能建工程，但 `project.yml` 让工程可版本化、可被 CI 复现，改文件比改 pbxproj 可靠。

## 3. CI 侧（不想买 Mac 的话，这条最省）

| 工具 | 说明 |
|---|---|
| GitHub Actions `macos-15` runner | Apple Silicon + 预装 Xcode 16，**公开仓库免费用**（私有仓库按 10× 分钟计） |
| `dtolnay/rust-toolchain` action | 一条 step 装好 rust + ios target |
| `actions/upload-artifact@v4` | 直接下 `Horizon.ipa` |

工作流已写好：[.github/workflows/ios-ipa.yml](.github/workflows/ios-ipa.yml)，push 一次约 8–12 分钟出 ipa。

## 4. 设备侧（装到手机）

| 方式 | 需要什么 | 限制 |
|---|---|---|
| **Sideloadly / AltStore**（Windows 即可） | Apple ID | 免费号 7 天过期、最多 3 个 App |
| **付费开发者账号** | $99/年 | 证书 1 年，Ad Hoc 100 台设备 |
| **TrollStore（巨魔）** | iOS 14.0–16.6.1 / 17.0，且设备在支持列表 | 装 adhoc 签名的 ipa，永久有效、不需要 Apple ID |
| **越狱** | 对应越狱工具 | `.app` 直接 scp 到 `/Applications/` 再 `uicache -a` |

## 5. 一句话判断

- **只验证“Horizon 能不能在 iOS 上跑起来”** → 只要第 3 节的 CI，零成本。
- **要真机调 Metal 性能 / 反复改 Swift 壳** → 才需要第 2 节的 Mac（二手 Mac mini M1 足够）。
- **要长期在自己手机上玩** → 先确认你的 iOS 版本有没有 TrollStore，否则准备一个付费开发者账号。
