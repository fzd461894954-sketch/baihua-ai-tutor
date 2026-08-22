# 白话 AI

白话 AI 是一个 macOS 菜单栏 AI 学习伙伴。它可以跟随你当前正在阅读的 AI 内容，在你主动点击“解释当前内容”后，生成一份更好懂的简短讲解。

## 启动

1. 打开 `AITutorMac.app`。
2. 在 macOS 菜单栏找到星光图标。
3. 点击“打开教学窗口”，或按 `Option-Space`。

当前是 V0.1 Internal Beta。没有 Developer ID 签名和 notarization 时，只建议在开发者本机或知道如何核对 Gatekeeper 提示的内部测试者机器上运行。

## 开启辅助功能

白话 AI 只在你主动开启内容跟随时使用 macOS 辅助功能：

1. 先把 Chrome 或 ChatGPT 切换到要解释的内容。
2. 打开白话 AI 菜单，点击“请求辅助功能权限…”。
3. 在“系统设置 → 隐私与安全性 → 辅助功能”中允许当前的白话 AI。
4. 回到目标 App，再打开白话 AI 菜单并点击“开始跟随当前应用”。

白话 AI 不需要 Screen Recording、Camera 或 Photos 权限。

## 配置 AI 模型

1. 在菜单栏中打开“设置…”。
2. 选择火山方舟 Ark 或自定义 OpenAI-compatible 服务。
3. 填写 endpoint、model 和 API Key，然后测试连接并保存。

API Key 只保存在 macOS Keychain，设置和日志中不显示明文。V0.1 的 Ark 推荐是 `doubao-seed-evolving` + `json_object`。不会自动覆盖你已保存的模型。

## 解释当前内容

1. 确认内容跟随已开始，并在目标 App 中停留到内容稳定。
2. 打开教学窗口。
3. 点击“解释当前内容”。

窗口会显示 loading，完整结果通过 Decode 和 Validate 后才会展示。一份 Lesson 包含白话解释、要点、术语，并可能包含比喻或例子。

## Pet、TTS 和 STT

- Pet 会显示当前状态。教学窗口隐藏时，新 Lesson 会通过 Pet Bubble 提醒；打开的是已有 Lesson，不会重新请求模型。
- Lesson 中的“讲给我听”使用 Apple 系统语音。不会自动播放。
- Push-to-Talk 只在你主动按住说话时请求麦克风和语音识别权限，松开后停止。
- “我的桌面老师…”可导入透明 PNG 作为自定义 Pet。

## Beta 限制

- Tutor 延迟受 Ark Provider / Model 影响。当前生产链路的完整讲解中位数约 23 秒。
- V0.1 不展示 partial JSON，只展示已完整验证的 Lesson。
- 本内部包没有 Developer ID 签名或 notarization，不是正式外部发行包。
