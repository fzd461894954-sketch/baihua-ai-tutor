# 白话 AI

白话 AI 是一个 macOS 菜单栏 AI 学习伙伴。它可以跟随你当前正在阅读的 AI 内容，在你主动点击“解释当前内容”后，生成一份更好懂的简短讲解。

## 启动

1. 打开 `AITutorMac.app`。
2. 在 macOS 菜单栏找到星光图标。
3. 点一下桌面的花花老师，就能在角色旁展开教学卡片。`Option-Space` 仍可打开独立教学窗。

当前修复版本为 V0.1.6（Build 7）。没有 Developer ID 签名和 notarization 时，只建议在开发者本机或知道如何核对 Gatekeeper 提示的内部测试者机器上运行。

## 开启辅助功能

白话 AI 只在你主动解释、提问或开启持续跟随时使用 macOS 辅助功能：

1. 先把 WorkBuddy、Chrome 或 ChatGPT 切换到要解释的内容。
2. 打开白话 AI 菜单，点击“请求辅助功能权限…”。
3. 在“系统设置 → 隐私与安全性 → 辅助功能”中允许当前的白话 AI。
4. 回到目标 App。持续跟随是可选功能，不影响单次解释。

白话 AI 不需要 Screen Recording、Camera 或 Photos 权限。

## 配置 AI 模型

1. 在菜单栏中打开“设置…”。
2. 选择火山方舟 Ark 或自定义 OpenAI-compatible 服务。
3. 填写 endpoint、model 和 API Key，然后测试连接并保存。

API Key 只保存在 macOS Keychain，设置和日志中不显示明文。V0.1 的 Ark 推荐是 `doubao-seed-evolving` + `json_object`。不会自动覆盖你已保存的模型。

## 解释当前内容

1. 在目标 App 中打开要解释的内容。
2. 点一下花花老师展开教学卡片。
3. 点击“解释当前内容”。

每次解释都会主动读取刚才使用的外部窗口，不需要预先开启持续跟随。窗口会显示 loading，完整结果通过 Decode 和 Validate 后才会展示。一份 Lesson 包含白话解释、要点、术语，并可能包含比喻或例子。

WorkBuddy 会在首次读取时自动启用它的 Electron 辅助功能树，并优先提取中央对话区，避免把左侧任务历史当成主要解读内容。

Chrome、Safari 和 ChatGPT/Codex 会优先读取中央对话区；没有聊天输入框的普通网页会回退到最大的网页内容区，不再把浏览器工具栏、标签页或聊天输入框当作正文。

## Pet、TTS 和 STT

- 花花老师会显示当前状态；新解释会直接出现在角色旁的教学卡片中，打开已有 Lesson 不会重新请求模型。
- 教学卡片里可以继续打字提问，也可以点一下麦克风开始说话，再点“结束并提问”；识别完成后会直接向花花老师提问。
- Lesson 中的“讲给我听”优先使用本机 Qwen3-TTS；本地服务不可用时自动回退到 Apple 系统中文语音，不会自动播放。
- “老师形象…”可导入透明 PNG 作为自定义角色。

第一次使用本地 AI 语音前，在仓库根目录运行 `./scripts/setup-local-voice.sh`。模型与推理均保留在这台 Mac 上，详见 [`docs/LOCAL_VOICE.md`](docs/LOCAL_VOICE.md)。

## Beta 限制

- Tutor 延迟受 Ark Provider / Model 影响。当前生产链路的完整讲解中位数约 23 秒。
- V0.1 不展示 partial JSON，只展示已完整验证的 Lesson。
- 本内部包没有 Developer ID 签名或 notarization，不是正式外部发行包。
