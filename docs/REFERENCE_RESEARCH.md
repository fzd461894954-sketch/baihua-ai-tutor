# 白话 AI V0.1 参考项目研究与许可证记录

> 研究日期：2026-08-14  
> 研究范围：公开仓库的 README、目录、与本项目相关的实现文件、LICENSE 及官方平台文档  
> 结论用途：只用于 STEP 0 架构决策；本项目当前没有复制任何参考仓库代码。

## 1. 先说明：同名项目的消歧结果

需求中的项目名有同名仓库或项目迁移。本文研究的是以下确切地址：

1. [openclaw/AXorcist](https://github.com/openclaw/AXorcist)
2. [lmquang/TextOCR](https://github.com/lmquang/TextOCR)
3. [Arthur-Ficial/apfel-quick](https://github.com/Arthur-Ficial/apfel-quick)
4. [harishkotra/hover](https://github.com/harishkotra/hover)
5. [ghostwright/shadow](https://github.com/ghostwright/shadow)
6. [screenpipe/screenpipe](https://github.com/screenpipe/screenpipe)

这里的 Shadow 是 Ghostwright 的开源本机上下文项目，不是 `shadow.do` 的同名商业会议产品。

## 2. 许可证总表

许可证结论以研究日拉取到的具体 commit 为准。仓库未来可能改许可证，所以真正引入依赖或代码前仍需重新检查。

| 项目 | 审查 commit | 仓库内许可证状态 | V0.1 代码使用决定 |
|---|---|---|---|
| AXorcist | `684693095215cccfaacba92e4e77cae9033b8f3e` | MIT，仓库有完整 `LICENSE` | 可以依法使用并保留声明；V0.1 只借鉴架构，暂不引入代码 |
| TextOCR | `2781065711d0350fc271688f5c157a928f02265b` | README 声称 MIT，但该 commit 的 Git tree 中没有 `LICENSE` 文件 | **不复制代码**；只使用公开的高层架构事实 |
| apfel-quick | `1ba3f08cad71065a31a458f0247410230fd89eb5` | MIT，仓库有完整 `LICENSE` | 可以依法使用并保留声明；V0.1 只借鉴交互和分层 |
| Hover | `38c8a71a600f5f252c0b4664b208a086b3a84763` | GPL-3.0-only | **闭源商业项目不复制、不改写、不移植其代码** |
| Shadow | `5eef3683b0654e1a1123fe63efa015e257efcdb5` | MIT，仓库有完整 `LICENSE` | 可以依法使用并保留声明；只借鉴事件/时间线思想 |
| Screenpipe | `cbac3ff9fcfb7bde227b0041e652210a317607a5` | Screenpipe Commercial License，当前不是开源许可证 | **不复制、不集成当前代码**；只研究公开架构描述 |

### 2.1 特别风险

#### TextOCR

[TextOCR README](https://github.com/lmquang/TextOCR/blob/main/README.md#license) 写着 MIT，并链接一个 `LICENSE`，但在本次审查的 commit 中没有这个文件。因此不能只凭 README 的一句话把源码当作已获得清晰 MIT 授权。

结论：除非作者补充有效 LICENSE 或另行书面授权，不复制 TextOCR 源码。屏幕截图、Vision OCR、菜单栏应用等通用做法由 Apple 官方文档独立实现。

#### Hover

[Hover LICENSE](https://github.com/harishkotra/hover/blob/main/LICENSE) 明确是 GPL-3.0-only。把其代码或衍生实现放进闭源商业产品，会带来强 copyleft 义务。

结论：只研究用户交互和模块职责。实现时依据本项目规格、Apple 官方 API 和独立测试重新编写，不复制代码结构、函数或具体表达。

#### Screenpipe

[Screenpipe LICENSE](https://github.com/screenpipe/screenpipe/blob/main/LICENSE.md) 在 2026 年改为自定义商业许可证。当前许可证明确限制在没有商业授权时把该代码嵌入商业产品、用于商业生产环境或构建竞争产品。许可证说明过去已按 MIT 发布的版本仍维持原许可证，但这不自动让当前主分支代码变成 MIT。

结论：V0.1 不引入当前 Screenpipe 代码、SDK 或内部实现。除非未来经过独立法律审查并固定具体历史 MIT commit，否则也不使用旧版本代码。

## 3. AXorcist

### 3.1 研究重点

- `AXUIElement`
- `AXObserver`
- Accessibility 查询与遍历
- 权限检查
- Swift concurrency

### 3.2 观察到的架构

AXorcist 把底层 C 风格 Accessibility API 包装成类型化 Swift 层：

- `Element` 封装 `AXUIElement`。
- 属性、动作、层级导航和搜索分为独立 extension/模块。
- `AXObserverCenter` 为同一 PID 管理和复用 observer。
- 订阅返回 token，最后一个 handler 移除时清理底层 notification。
- `NotificationWatcher` 管理 start/stop 和生命周期清理。
- 权限 helper 封装 `AXIsProcessTrusted` 和异步状态观察。
- 文本提取有最大深度，避免无限递归整个可访问树。

### 3.3 对白话 AI 有价值的做法

1. **把 AX 原始调用隔离在 Context/Accessibility。** 其他模块只接收 `AppContext`。
2. **按 PID 管理 observer 生命周期。** App 切换或退出时可靠清理。
3. **订阅使用 token。** 避免匿名闭包无法注销和 observer 泄漏。
4. **类型化错误。** 区分未授权、无属性、无元素、超时和目标退出。
5. **遍历必须有预算。** 除深度外，本项目再增加节点、字符和时间上限。

### 3.4 不直接照搬的部分

- AXorcist 同时支持“读”和“控制”UI，而白话 AI V0.1 只读。
- 其完整命令系统、模糊搜索和动作层超出原型需要。
- 本项目不会暴露 click、set value、type 等操作接口。
- 本项目不需要为了少量读取能力引入整个自动化库；STEP 2 先用最小原生封装验证。

### 3.5 许可证

[MIT License](https://github.com/openclaw/AXorcist/blob/main/LICENSE)，版权声明为 2025 Peter Steinberger。MIT 允许商业使用、修改和分发，但复制或实质性使用时必须保留版权和许可声明。

## 4. TextOCR

### 4.1 研究重点

- ScreenCaptureKit
- Vision OCR
- Menu bar app
- 全局快捷键

### 4.2 观察到的架构

项目采用相对清晰的 service/coordinator 划分：

```text
AppKit/MenuBar
    → CaptureCoordinator
        → ScreenCaptureService
        → OCRService
        → ClipboardService
```

与本项目相关的公开实现思路包括：

- `SCShareableContent` 获取可捕获显示内容。
- `SCScreenshotManager` 获取单帧截图，而不是启动长期录像。
- `VNRecognizeTextRequest` 在本机识别文字。
- 多显示器场景需要处理全局坐标和 display-local 坐标。
- 菜单栏控制器与 capture workflow 分离。
- 全局快捷键使用独立 package，而不是把监听代码塞进 View。

### 4.3 对白话 AI 有价值的做法

1. OCR 采用“capture → recognize → return text”的独立服务链。
2. 单帧截图比默认持续 SCStream 更符合白话 AI 的隐私目标。
3. OCR 结果仍然只是 Context Provider 输出，必须继续经过 diff。
4. 屏幕和 Vision 服务应当可用 fixture/mock 测试，而不是由 UI 直接调用。

### 4.4 发现的问题与不采用项

- 当前仓库 README 的 sandbox 说明与 entitlements 文件配置不一致。
- README 声称 MIT，但当前 commit 缺少 LICENSE。
- 项目示例是区域选择截图；白话 AI 需要优先匹配并捕获一个明确的 `SCWindow`。
- 项目直接同步执行 OCR 的模式不适合频繁语义跟随；白话 AI 需要后台任务、取消和退避。
- 不采用其通知 API、日志风格或任何源码片段。

权限和 ScreenCaptureKit 配置以 Apple 官方文档和 STEP 6 真机验证为准，不把该仓库当作权限权威。

### 4.5 许可证

许可证状态不完整。README 的 MIT 声明不足以替代缺失的 LICENSE 文件，所以本项目按“不可复制源码”处理。

## 5. apfel-quick

### 5.1 研究重点

- Spotlight 风格悬浮窗口
- `NSPanel` + SwiftUI
- 全局快捷键
- Streaming UI

### 5.2 观察到的架构

apfel-quick 是 `LSUIElement` 菜单栏 App，主要结构是：

- App/AppDelegate 负责 panel、热键、状态栏和生命周期。
- SwiftUI View 通过 `NSHostingController` 放进 `NSPanel`。
- ViewModel 管理输入、流状态、输出和取消。
- Service 把模型输出表示成 `AsyncThrowingStream`。
- Panel 可以成为 key window 以接收文本输入，但不成为 main window。
- Panel 加入所有 Spaces，并作为全屏辅助窗口。
- Esc 隐藏，热键重新显示。
- 设置、模型服务和渲染逻辑分开。

### 5.3 对白话 AI 有价值的做法

1. `NSPanel` 负责窗口行为，SwiftUI 只负责内容。
2. 自定义 panel controller 持有窗口，避免 SwiftUI View 自己管理 AppKit 生命周期。
3. Streaming 用 `AsyncThrowingStream` 表达，Task 取消可以贯穿 ViewModel 和服务。
4. 首屏先显示，不因后台服务初始化阻塞 UI。
5. Panel 尺寸和内容状态由单独策略计算，避免所有窗口逻辑堆进 View。

### 5.4 不直接照搬的部分

- apfel-quick 面向 macOS 26 的本机 Foundation Models；白话 AI 目标是 macOS 14+。
- 白话 AI 不是输入 Prompt 的 Spotlight，它需要靠近目标 App 的教学侧栏。
- 参考项目的热键实现与 Accessibility 权限流程不能直接决定本项目方案；STEP 1 要确保热键不会在 Welcome 前意外触发权限请求。
- 白话 AI 的输出是结构化多区块，不是单段 Markdown。

### 5.5 许可证

[MIT License](https://github.com/Arthur-Ficial/apfel-quick/blob/main/LICENSE)，版权声明为 2026 Arthur Ficial。复制实质性代码时必须保留声明；本阶段没有复制。

## 6. Hover

### 6.1 研究重点

- 当前 App context
- 选中文字
- 悬浮 AI
- Streaming
- Keychain 和隐私披露

### 6.2 观察到的产品/架构思想

Hover 的模块把以下职责分开：

- 全局触发
- Accessibility 屏幕文字上下文
- 可选截图上下文
- OpenAI-compatible streaming client
- Keychain
- 浮动 Panel
- 设置和 Provider 配置

它强调按需触发、明确说明可能离开 Mac 的上下文、远程 Provider 与本地 Provider 的差异，这些产品原则与白话 AI 高度相关。

### 6.3 对白话 AI 有价值的做法

1. 用户应看得见本次请求用了哪些上下文。
2. Keychain 和 Provider 配置必须与 UI 解耦。
3. 网络连接测试应该真的经过 streaming 路径，而不只是 ping URL。
4. `URLSession` 应避免 cookie/cache，并谨慎处理跨主机 redirect。
5. 流式请求的取消、完成和错误应有清晰 UI 状态。

### 6.4 不采用项

- 不复制任何 Hover 源码、类结构、Prompt 或实现细节。
- V0.1 不通过模拟 Command-C/Command-V 自动替换其他 App 内容。
- V0.1 不自动粘贴、输入或操作目标 App。
- 截图只作为 Accessibility 失败后的 OCR 输入，不作为默认视觉模型上下文。

### 6.5 许可证

[GPL-3.0-only](https://github.com/harishkotra/hover/blob/main/LICENSE)。本项目按 clean-room 原则独立实现，不复制或改写 GPL 代码。

## 7. Shadow

### 7.1 研究重点

- context timeline
- AXUIElement
- ScreenCaptureKit
- NSWorkspace
- 事件式上下文

### 7.2 观察到的架构

Shadow 把不同来源的上下文视为按时间对齐的 track：

- ScreenCaptureKit 屏幕轨
- Accessibility tree 快照
- NSWorkspace App/窗口变化
- 输入、音频、文件等其他轨
- 本地 timeline index

与本项目直接相关的设计：

- App 激活通过 `NSWorkspace` notification 感知。
- 窗口标题变化不能完全依赖 App 切换事件，因此有低频补充检查。
- Accessibility 快照带时间、App、窗口和 hash，可判断是否真正变化。
- OCR 在后台处理，并先做近似画面去重。
- 权限状态、暂停、排除 App 和本地数据路径是明确产品能力。

### 7.3 对白话 AI 有价值的做法

1. 所有上下文都带时间戳、App、窗口和来源。
2. App switch 事件与低频补漏可以并存，但补漏必须受状态门控。
3. 捕获与索引/理解分开，避免采集层直接调用 AI。
4. 变化 hash、时间窗口和 source identity 可以帮助避免重复处理。
5. 权限和暂停是架构状态，不只是设置页上的开关。

### 7.4 明确不采用的范围

Shadow 是长期个人上下文记录系统，持续采集屏幕、输入、音频等多种信号。白话 AI V0.1 明确不做：

- 持续视频
- 键盘记录
- 音频记录
- 全天 timeline
- 长期保存完整 AX tree
- 计算机自动操作
- 本机大模型下载和训练

只采用“事件按时间归一化”和“变化后再处理”的思想。

### 7.5 许可证

[MIT License](https://github.com/ghostwright/shadow/blob/main/LICENSE)，版权声明为 2026 Ghostwright。当前允许商业使用并要求保留声明；本阶段没有复制代码。

## 8. Screenpipe

### 8.1 研究重点

- Accessibility-first
- OCR fallback
- Event-driven capture
- Context architecture

### 8.2 公开架构结论

[Screenpipe README](https://github.com/screenpipe/screenpipe#event-driven-screen-capture) 当前描述的核心路径是：

```text
App 切换 / 点击 / 输入停止 / 滚动等有意义事件
    → 同时间戳采集 screenshot + accessibility tree
    → Accessibility 可用时优先使用结构化文字
    → Accessibility 不可用时 OCR fallback
    → 无事件时只有低频 idle fallback
```

这验证了白话 AI 的总体方向：Accessibility 的准确性和资源占用通常优于 OCR；高频重复画面应先去重；事件式采集比固定高帧率录屏更合适。

### 8.3 对白话 AI 有价值的做法

1. “Accessibility first, OCR fallback”作为明确优先级，而不是两条路径同时常开。
2. App/窗口/时间/source 一起进入上下文身份。
3. 事件触发后仍要有 idle fallback，但必须低频并可停止。
4. 内容类型和 App allow/deny 规则应是确定性门控，而不是只靠 Prompt 要求模型保密。
5. 本地优先、最小化云端上下文是产品信任基础。

### 8.4 不采用项

- 不复制 Screenpipe 当前源码、crate、SDK、配置或数据库设计。
- 不做 24/7 屏幕/音频记录。
- 不做跨平台 Rust/Tauri 架构。
- 不做完整搜索、时间线和 Agent 数据权限系统。
- 不依据 README 中的性能数字为白话 AI 做性能承诺。

### 8.5 许可证

当前是 [Screenpipe Commercial License](https://github.com/screenpipe/screenpipe/blob/main/LICENSE.md)，不是 MIT 主分支。没有单独商业授权时，本项目不使用其当前代码。

## 9. 官方文档交叉验证

参考仓库只能提供经验，macOS API 行为和 OpenAI 接口形态最终以官方文档与真机实验为准。

### Apple

- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)：App 激活等工作区事件。
- [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)：Accessibility 信任检查/请求入口。
- [Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)：通过 `SCShareableContent` 和 `SCContentFilter` 选择显示器/App/单窗口。
- [SCContentFilter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter)：限定只捕获指定窗口或 App。
- [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)：按 filter 捕获单帧。
- [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)：本机 OCR 及语言、速度/精度选项。

### OpenAI

- [Chat API Reference](https://developers.openai.com/api/reference/resources/chat)：Chat Completions 的 streaming chunk、delta、stream options 和结构化格式。

架构决定：为广泛的“OpenAI-compatible”服务实现 Chat Completions 适配器，但不假设所有服务都支持 OpenAI 的全部参数。JSON Schema、usage chunk 等都需要 capability/连接测试和降级逻辑。

## 10. 本项目的许可证与 clean-room 规则

### 10.1 STEP 0 结论

- 当前工作区只新增本项目自己的 Markdown 文档。
- 没有复制任何参考项目源码。
- 没有把参考仓库加入 Git submodule、Swift Package 或 vendored directory。

### 10.2 以后每次引入第三方代码前

必须记录：

1. 仓库 URL
2. 固定 commit/tag
3. 具体使用文件/Package
4. SPDX 许可证
5. 版权声明
6. 是否需要 NOTICE / source disclosure
7. 是否允许商业闭源分发
8. 依赖的传递许可证

### 10.3 当前允许与禁止

| 来源 | 可研究高层思想 | 可直接复制代码 | 条件 |
|---|---:|---:|---|
| Apple 官方 API 文档/示例 | 是 | 依 Apple示例许可条款单独核查 | 实现优先依据公开 API，不复制不必要大段示例 |
| AXorcist MIT | 是 | 可以，但当前不计划 | 保留 MIT 版权/许可声明 |
| apfel-quick MIT | 是 | 可以，但当前不计划 | 保留 MIT 版权/许可声明 |
| Shadow MIT | 是 | 可以，但当前不计划 | 保留 MIT 版权/许可声明 |
| TextOCR 当前 commit | 是 | 否 | LICENSE 文件缺失，等待作者修复或授权 |
| Hover GPL-3.0-only | 是 | 否 | 闭源商业项目采用 clean-room 独立实现 |
| Screenpipe 当前主分支 | 是 | 否 | 当前商业许可证限制集成/商业/竞争性使用 |

### 10.4 计划中的小型依赖

STEP 1 如果选择 [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 实现可配置全局热键，必须在加入 Package 前再次确认 tag 和 MIT License，并在第三方声明中记录。若使用原生 Carbon hotkey 封装，则不需要这个依赖。该选择在 STEP 1 根据权限体验和维护成本确定。

## 11. 最终研究结论

六个项目共同支持一个方向：

```text
用户明确开启
    → NSWorkspace 定位当前 App
    → Accessibility 读取结构化可见文字
    → 事件触发，低频轮询补漏
    → 变化检测与语义缓冲
    → Accessibility 失败时才对指定窗口做单帧 OCR
    → 最小文字上下文进入 Tutor Engine
    → 流式、结构化地显示教学结果
```

白话 AI 不需要复制这些项目才能实现该架构。V0.1 优先用 Apple 原生 API 和本项目自己的小型协议层独立实现，既控制隐私和复杂度，也避免 GPL、缺失许可证和 Screenpipe 商业许可证带来的风险。

