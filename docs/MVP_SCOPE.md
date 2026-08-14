# 白话 AI V0.1 范围

> 文档状态：STEP 0 范围基线  
> 更新日期：2026-08-14  
> 原则：验证“零基础用户是否能看懂 AI 正在做什么”，不以功能数量衡量成功。

## 1. V0.1 要验证的核心假设

当用户在 ChatGPT 或 Codex 中看到一段难懂的新回答时，白话 AI 能够：

1. 在不控制目标 App 的前提下获取可见的新文字。
2. 不重复发送和解释已经处理过的整段内容。
3. 在侧边悬浮窗中快速说明“做什么、为什么、风险、下一步”。
4. 让用户通过“我还是没懂”获得更适合自己的第二次解释。
5. 对已经反复学过的知识逐渐减少基础说明。

如果 V0.1 不能可靠完成这五件事，增加登录、课程、社区、自动操作等功能都没有意义。

## 2. 目标用户

- 没有编程基础，但正在使用 Codex 完成软件工作的人。
- 使用 ChatGPT 学习或完成工作，却常被专业术语卡住的人。
- 愿意明确授权读取当前 AI 窗口文字，并希望随时知道软件正在读取什么的人。

V0.1 不以专业开发者的效率工具为第一目标，也不承诺替代专业安全、法律、医疗或财务意见。

## 3. V0.1 做什么

### 3.1 MenuBar App

提供原生菜单栏入口，显示：

- 当前是否跟随
- 当前目标 App
- 打开教学窗口
- 暂停/继续
- 设置
- 退出

验收标准：

- 启动后不出现传统大型主窗口。
- 用户可以只通过菜单栏完成打开、暂停和退出。
- 暂停状态不能与“窗口暂时隐藏”混淆。

### 3.2 Floating Panel

提供 SwiftUI 内容的原生 `NSPanel`。

验收标准：

- 默认 Option + Space 显示/隐藏。
- Esc 隐藏。
- 可拖动、可固定、可在目标 App 旁边保持悬浮。
- 支持 macOS 深色/浅色外观，文字对比度足够。
- 不遮挡成传统全屏聊天窗口。

### 3.3 Accessibility Permission

首次需要读取文字时，先用白话说明用途，再由用户点击请求辅助功能权限。

验收标准：

- 不在首次启动瞬间连弹多个系统权限。
- 明确写出“只读取已显示文字，不自动点击或操作其他软件”。
- 权限被拒绝或撤销时有可理解的恢复步骤。
- 授权状态变化后无需用户猜测当前是否生效。

### 3.4 当前 App 检测

通过 `NSWorkspace` 获取前台 App，并在菜单栏/设置中展示。

验收标准：

- ChatGPT、Codex、Safari、Chrome 之间切换时状态正确更新。
- 切换目标后不会继续使用上一个窗口的 diff 历史。
- 未支持 App 默认不读取内容。

### 3.5 Accessibility 读取文字

从当前目标 App 的 focused window 和可访问文字区域提取屏幕上已经可见的文字。

验收标准：

- 有深度、节点数、字符数和耗时预算。
- 能区分“读到内容”“只读到控件标签”“完全不可读”。
- Debug 面板能显示 App、Bundle、窗口、原始 AX 文本和质量判断。
- 在 `docs/ACCESSIBILITY_TEST.md` 如实记录四个目标 App 的结果。

说明：V0.1 不承诺每一个 ChatGPT/Codex 版本都能通过 AX 完美读取；STEP 2 的目的就是先取得真实数据。

### 3.6 手动 Explain

用户可以点击“解释当前新增内容”，由 Tutor Engine 处理当前 diff。

验收标准：

- 自动跟随关闭时仍可由用户明确触发一次读取和解释。
- 没有新增内容时不重复调用 AI，并说明“暂时没有检测到新内容”。
- 发送云端前已经在设置中披露 Provider 和发送内容类型。

### 3.7 Context Diff

比较同一 App/窗口的 previous context 和 current context，只输出新增的稳定内容。

验收标准：

- 重复输入返回空增量。
- 追加句子只返回追加部分。
- 能处理常见换行重排和 token 逐步增长。
- App/窗口切换不会串上下文。
- OCR 小幅识别抖动不会反复触发整段解释。
- FULL CONTEXT / NEW CONTEXT Debug UI 可验证结果。
- 核心边界场景有单元测试。

### 3.8 Tutor Engine

输出以下结构：

- AI 正在做什么
- 大白话解释
- 为什么
- 最小必要原理
- 最多 3 个术语
- 风险等级与说明
- 用户下一步
- 本次学习点

验收标准：

- 风险等级只允许 `none / low / medium / high`。
- 输出缺字段或 JSON 无法解析时，不显示为可靠结果。
- 第一次解释默认 3～5 句，避免用更多术语解释术语。
- 无法确认时明确说“目前只能根据屏幕内容推测”。
- 不要求、不输出模型隐藏 Chain of Thought。
- `Build succeeded` 不被解释成“完全没有 Bug”。

### 3.9 OpenAI-compatible API

提供 Base URL、Model、API Key 和兼容能力设置。首个适配器支持 Chat Completions 风格的 SSE 流式文字。

验收标准：

- Tutor Engine 不直接依赖具体厂商 SDK。
- 能测试连接并区分鉴权失败、限流、超时和格式错误。
- 不支持 JSON Schema 的兼容服务仍可以退化为严格 JSON Prompt。
- 云端只发送生成解释所需的最小文字上下文。

### 3.10 Streaming

Provider 返回内容时，悬浮窗逐步出现已经稳定解析的教学区块。

验收标准：

- 请求可取消。
- SSE 半行、多个事件、`[DONE]` 和异常断流都有测试。
- 结构化结果最终必须完整校验。
- 不因目标 AI 每输出一个 token 就新建一次 Tutor 请求。

### 3.11 Semantic Buffer

在完整句号、稳定换行、短暂静止、达到长度或完整工具状态时才提交新增内容。

验收标准：

- 连续 token 被合并。
- `Build succeeded` 等短状态不会因为字数少永远不触发。
- 不跨 App/窗口合并。
- 自动跟随关闭后清空待发送缓冲。

### 3.12 “我还是没懂”

支持：

- 再简单一点
- 举个生活例子
- 从头解释
- 讲深一点

验收标准：

- 每种方式都复用同一 Tutor Engine 协议，不在 View 中拼 Prompt。
- 重新解释时带上原知识点和必要上下文，不上传完整历史。
- 点击后降低相应知识点熟悉度。

### 3.13 Keychain

所有 API Key 通过 `CredentialStore` 保存到 macOS Keychain。

验收标准：

- 源码、Info.plist、UserDefaults、应用日志和诊断导出中没有 API Key。
- 修改 Base URL/Provider 时不会误用其他服务的 Key。
- 删除 Provider 配置时可以同步删除对应 Keychain item。

### 3.14 本地基础知识记录

保存知识点、熟悉程度、最近解释时间、解释次数和“没懂”次数。

验收标准：

- 熟悉度始终在 `0...1`。
- 只保存知识元数据，不保存整段聊天或截图。
- 用户可以清空本地知识记录。
- 设置支持“完全零基础 / 简单 / 普通 / 专业”。

### 3.15 自动跟随

在用户打开“跟随 AI”后，事件和受限 polling 检测新增语义块并自动解释。

验收标准：

- 开启时才读取目标内容。
- 暂停后停止 AX observer、polling、OCR、网络请求和缓冲。
- 高频变化不会产生请求风暴。
- 界面始终能看见当前读取 App 和来源。

### 3.16 OCR fallback

Accessibility 质量不足时，用户可以单独授权指定窗口的屏幕读取。

验收标准：

- 不提前请求 Screen Recording。
- 只捕获目标窗口单帧，不持续录制整个桌面。
- 图片只在内存中完成 Vision OCR，默认不保存、不上传。
- OCR 结果仍经过质量判断、Context Diff 和 Semantic Buffer。
- 未授权、窗口匹配不唯一、截图失败都有清楚提示。

## 4. V0.1 明确不做什么

### 产品功能

- 登录注册
- iCloud
- 多设备同步
- 课程系统
- 社区
- 支付
- 企业管理
- 完整知识图谱
- Windows
- iOS
- App Store 上架
- 自动更新和商业发布流水线

### 自动化能力

- 自动点击其他 App
- 自动输入或替换用户内容
- 自动执行终端命令
- Agent 自动完成任务
- 自动数据库操作
- 自动 Git push
- 自动部署或发布
- 自动购买服务

### 上下文与媒体

- 持续录制整个桌面
- 后台保存全天截图时间线
- 麦克风和系统音频录制
- 键盘输入记录
- 浏览器扩展
- IDE 插件
- 读取未显示在屏幕上的私有对话历史
- 把截图发送给云端视觉模型

### AI Provider

- Anthropic 专用实现
- Gemini 专用实现
- Ollama 专用实现
- LM Studio 专用实现
- 自动模型路由
- 云端账号体系
- Provider 费用代付

说明：如果 Ollama 或 LM Studio 自身提供所配置的 OpenAI-compatible endpoint，通用适配器未来可能连通；V0.1 不承诺专用发现、安装和故障诊断。

### 教学系统

- 完整课程路径
- 考试或测验
- 成就/积分/游戏化
- 自动生成长期学习计划
- 专业领域知识库
- 对用户能力做高精度心理或教育评估

## 5. 不可妥协的隐私与安全要求

以下不是“以后优化”，而是 V0.1 的完成条件：

1. 未开启跟随时不读取目标 App 内容。
2. 未经用户点击不请求 Accessibility 或 Screen Recording。
3. Accessibility 能工作时不使用 OCR。
4. OCR 只针对已确认的目标窗口，图片处理后释放。
5. 暂停必须停止整个采集与网络链路。
6. 设置中持续显示当前读取对象、读取方式、屏幕录制状态和云端发送状态。
7. API Key 只在 Keychain。
8. 原始上下文不进入普通日志。
9. 默认不持久化截图、OCR 图像、完整对话或 Prompt。
10. 不宣称获取隐藏思维链，不把推测说成事实。

任何一个条件没有达到，都不能称为 V0.1 完成。

## 6. 支持矩阵

| 场景 | V0.1 目标 | 备注 |
|---|---|---|
| ChatGPT macOS App | 优先支持 | 先测 AX；失败再走用户授权 OCR |
| Codex macOS App | 优先支持 | 需要识别回答、命令、测试、Build、Git 等可见状态 |
| ChatGPT in Safari | 实验性支持 | Web Area 结构受网页和浏览器版本影响 |
| ChatGPT in Chrome | 实验性支持 | 可访问树启用和网页 ARIA 质量会影响结果 |
| Claude/其他 AI App | 架构可扩展，不是 V0.1 验收对象 | 未经测试不宣传支持 |
| 非 AI App | 默认不读取 | 用户明确允许的手动调试除外 |

## 7. 分阶段交付

### STEP 0：架构分析

产出：

- `docs/ARCHITECTURE.md`
- `docs/MVP_SCOPE.md`
- `docs/REFERENCE_RESEARCH.md`

完成条件：架构、范围、目录、风险、参考许可证和开发顺序清楚；不写 App 代码。

### STEP 1：最小 App

只做：

- MenuBarExtra
- Floating NSPanel
- Option + Space
- Esc

不读屏、不接 AI。

### STEP 2：Accessibility 实验

只做：

- 渐进式辅助功能权限
- 当前 App/窗口检测
- AX 文字读取
- Debug 面板
- `docs/ACCESSIBILITY_TEST.md`

质量闸门：四个目标 App 都有真实记录，失败也必须记录。

### STEP 3：Context Diff

只做：

- previous/current 比较
- FULL/NEW Context Debug
- 纯逻辑测试

质量闸门：重复、追加、流式增长、重排、滚动、窗口切换、OCR 抖动测试通过。

### STEP 4：Tutor Engine

只做手动触发：

- Keychain
- OpenAI-compatible Provider
- SSE streaming
- 结构化教学输出
- “我还是没懂”
- 本地知识记录基础版

### STEP 5：自动跟随

增加：

- AX 事件
- debounce/coalescing
- Semantic Buffer
- 受限 fallback polling
- 完整暂停语义

### STEP 6：OCR fallback

增加：

- 屏幕读取说明和权限
- 目标窗口匹配
- 单帧 ScreenCaptureKit
- Vision OCR
- OCR diff 与性能验证

每个 Step 完成后暂停，等待用户确认再进入下一步。

## 8. V0.1 Definition of Done

V0.1 只有在以下场景可以稳定演示时才完成：

1. 用户打开 Codex，白话 AI 正确显示“正在跟随：Codex”。
2. Codex 出现 `Running npm install`，白话 AI 在一个稳定语义块后解释“正在安装项目需要的组件”。
3. 相同内容继续停留在屏幕上，不重复调用 Tutor。
4. Codex 出现 `Build succeeded`，解释明确说“构建通过不等于完全没有 Bug”。
5. 出现数据库 migration、删除、权限或密钥相关内容时，风险至少得到保守提示。
6. 用户点击“举个生活例子”，得到更简单的第二次解释。
7. 用户暂停跟随后，内容读取、OCR 和网络请求都停止。
8. 设置页能回答“现在读什么、怎么读、会发给谁”。
9. API Key 不存在于项目文件和 UserDefaults。
10. ChatGPT/Codex 的 AX 或 OCR 局限已在文档中如实披露。

## 9. 产品成功指标

原型期先观察定性和轻量定量指标，不接入第三方埋点 SDK：

- 用户能否正确复述 AI 当前动作。
- 首次解释后是否还需要“我还是没懂”。
- 重复解释率。
- 从屏幕变化到首个教学区块出现的时间。
- Accessibility 成功率与 OCR fallback 比例。
- 每个稳定语义块触发的 Tutor 请求数。
- 用户是否能找到并理解“暂停全部读取”。

这些指标优先通过本地 Debug 统计和人工测试收集。任何遥测方案都属于后续决策，不能在 V0.1 中静默加入。

