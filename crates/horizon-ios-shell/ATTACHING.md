# Horizon 的 iOS 外壳：把它接到真游戏上

这个 crate 现在只证明一件事：**CAMetalLayer → wgpu Metal → 每帧一次 present 在 iOS 上能跑**
（已经在 Windows 上用 `cargo check --target aarch64-apple-ios` 验证过类型与 API 全部成立，
链接与实际出图要 macOS/CI）。接下来是把它换成真游戏，按下面顺序做，每步都能单独验证。

## 0. 现状对照

| 位置 | 桌面端做了什么 | iOS 外壳现在 | 接上去要做的事 |
|---|---|---|---|
| `crates/horizon-client/src/main.rs` | `horizon_client::entry::main()` 起 winit 事件循环 | UIKit 起 `CADisplayLink` | 把 `entry::main` 拆成 `init(state)` + `tick(dt)` |
| 窗口 / surface | `winit` 窗口 + `wgpu::Surface` | `CoreAnimationLayer` surface | 把 `gfx` 的 surface 改成外部注入 |
| 输入 | winit 键鼠 + `gilrs` 手柄 | 裸触摸点进 `hz_touch` | 触摸 → `Action` 映射 |
| 资源根 | `~/.minecraft` / `--minecraft-dir` | 沙盒 `Application Support/horizon` | 把资产根改成可注入（`hz_assets_root()`） |
| 声音 | `cpal` | 无 | `cpal` 的 `coreaudio` 后端，或 AVFoundation |
| 线程 | rayon 全局池，按核数 | iOS 核数少 | 见 #1751 的辅助线程上限 |

## 1. 先拆 entry（不改行为）

`entry::main()` 现在是「建窗口 → 建 gfx → 跑循环」。拆成：

```rust
pub struct Rt { /* device, queue, surface, world, renderer… */ }
pub fn init(surface: wgpu::Surface<'static>, size: (u32, u32), assets: PathBuf) -> Rt;
pub fn tick(rt: &mut Rt, dt: f32, input: &InputFrame);
```

`horizon-client` 的桌面 `main` 变成 20 行的驱动，iOS 外壳的 `hz_frame` 也是 20 行的驱动。
这一步不动渲染和 gameplay 代码，纯搬运，但它是后面所有事情的前提。

## 2. 注入 surface

`hz_create` 里已经有：

```rust
let surface = unsafe {
    instance.create_surface_unsafe(wgpu::SurfaceTargetUnsafe::CoreAnimationLayer(layer_ptr))
}?;
```

把 `Rt::init` 改成接收这个 `surface`，桌面端则从 `winit::Window` 造一个。
两边共用 `SurfaceConfiguration`（`surface.get_default_config` 已经处理了格式/色彩空间），
唯一区别是 iOS 上 `drawableSize` 是 `bounds × contentScaleFactor` —— `GameView.swift` 已经这么算。

## 3. 触摸 → Action

`crates/horizon-client-input/src/actions.rs` 里的 `Action` 是全项目的输入契约，游戏代码只问
`held(action)`。所以触屏不是「再写一套输入」，而是**多一个 action 来源**：

```
左半屏拖 = 移动摇杆（Forward/Back/Left/Right 的模拟量）
右半屏拖 = 视角（Game::look_turn）
单击方块 = Attack，长按 = 连续 Attack（带冷却节流）
放置键 = Use
快捷栏 = 屏幕底部 9 格
```

把 `hz_touch` 收到的 `(id, phase, x, y)` 攒成 `InputFrame`，在 `tick` 里喂给同一个 resolver。
手柄（`gilrs` 的 iOS GameController 后端）走同一条路，不需要分支。

## 4. 资源根

`AssetsStore.swift` 把数据放在 `Application Support/horizon/{assets,data}`，
`hz_set_assets_root` 把它交给 Rust。需要改的是 `horizon-assets` / `horizon-prepare` 里
读 `~/.minecraft` 的那些函数，让它们接受显式根路径（`hz_assets_root()` 已经给出 getter）。

## 5. iOS 特有的坑（按会咬人的顺序）

1. **jetsam**：iPhone 上可用内存比桌面少一个数量级。`RD32` 的工作集 1.2–1.7GB 会直接把进程干掉。
   先固定 `render distance ≤ 8`、远景雾化、贴图流式加载，再谈调优。
2. **`forbid(unsafe_code)`**：`horizon-client` 的 `main.rs` 顶上有这行，外壳 crate 没有。
   桥接代码全部留在这个 crate 里，就不会污染上游的 unsafe 纪律。
3. **后台挂起**：`applicationDidEnterBackground` 里必须把世界落盘，否则切出去回消息就可能丢存档。
4. **热量**：`CADisplayLink` 会自己降频，但持续 120Hz 在 iPhone 上十分钟就烫。给一个 30/60/120 的帧率选项。
5. **音频**：`cpal` 在 iOS 上要用 `AVAudioSession` 配好 category，否则静音键/耳机切换会杀声卡。
6. **在线模式**：微软登录要 `ASWebAuthenticationSession` + 本地回环回调，`ureq` 的请求放在后台线程。
