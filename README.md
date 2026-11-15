# ihorizon

在这里感谢[Horizon](https://github.com/horizon-rust/horizon)开源的客户端，才让本项目实现

**Minecraft: Java Edition（26.3）在 iPhone / iPad 上的原生运行环境。**

不是模拟器，不是 Java 虚拟机，不是把 jar 塞进启动器。ihorizon 把 [Horizon](https://github.com/horizon-rust/horizon) —— 一个用 Rust 从零重写的 Minecraft: Java Edition 客户端 —— 交叉编译成 arm64 的 iOS 可执行文件，并用 Metal 直接绘制。

所以它启动时没有 JIT，没有 HotSpot，没有 GL4ES 翻译层：屏幕上跑的就是原生 ARM64 代码。（造就了此游戏极致的优化）

```
iPhone (Metal)  ←  wgpu  ←  horizon-client (Rust)
                                ↑
                    winit 的 iOS 后端 (UIApplicationMain)
```

---

## 它是什么

| | |
|---|---|
| 渲染 | wgpu 30，Metal 后端，`CAMetalLayer` 直接呈现 |
| 窗口 / 输入 | winit 0.30.13 的 iOS 后端；触摸在 Rust 侧转成指针与虚拟手柄 |
| 平台 | iPhone / iPad，iOS 15.0+，arm64，横屏 |
| 游戏内容 | 生存、创造、旁观；三维度、红石、命令、多人（含正版验证）、局域网 |
| 资源 | 玩家自己的 Minecraft 26.3 文件，经 `horizon-prepare` 抽取后导入 |
| 分发形态 | 未签名 `.ipa`，自签安装；不随包分发任何 Mojang 资源 |

## 它不是什么

- **不是 PojavLauncher 的替代品**。PojavLauncher 跑的是真正的 Java 版服务端逻辑（JVM + JIT + GL 翻译），兼容所有 Fabric/Forge mod，但受 JIT 限制性能有限。ihorizon 跑的是 Rust 重写版，**不能加载 Java mod**。
- **不是官方产品**。与 Mojang、Microsoft、Horizon 上游都没有关系。
- **不含游戏资源**。包里只有引擎；方块贴图、音效、语言文件都要你自己从正版客户端抽取后导入。

---


## 操作

- **点面板外空白**：关闭当前容器界面（背包、工作台、熔炉、箱子、潜行盒……）；
- 布局可改：`Documents/ihorizon/touch_layout.json`，每键独立大小与位置

## 光影

- 编写了一个原生光影包 **Reimagined**（`shaderpacks/reimagined/`，纯 WGSL，不经过 GLSL 翻译层）：天空渐变、日落带、昼夜色温、方块光暖色偏移、泛光、色调映射与暗角。
- 效果完全对标Complementary Shaders - Reimagined 由Complementary Shaders - Reimagined 参考转译而来 感谢
- 性能优化相当高效，iphone11 60fps+
- 未来还会推出更多光影适配

也支持 Iris/OptiFine 格式的 `.zip` 光影包（放在 `Documents/ihorizon/shaderpacks/`），但兼容层有明确缺口：不支持几何着色器、compute 型 pass、storage buffer 里的 bool、imageLoad/Store，因此体积光、SSAO、水面反射、彩色光、TAA 这类效果无法完整呈现。想要全效只能用 Horizon 原生格式自己写。

## Mod

- **`.hmod`**：纯数据内容包（方块、物品、配方、效果），可以装。
- **`.hnmod`**：原生 Rust 扩展，改的是客户端源码，需要启动器现场编译。
- **Fabric / NeoForge 的 jar**：**不能装**。这里没有 JVM，也没有 `net.minecraft` 的 Java 类。
- 未来还会推出更多mod适配

---

## 许可

见 [LICENSE](LICENSE)：**允许个人学习、研究、在自己设备上使用与修改；禁止任何形式的售卖与商业使用。**
