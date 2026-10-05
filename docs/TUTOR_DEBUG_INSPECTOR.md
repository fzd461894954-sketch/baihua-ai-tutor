# Tutor Debug Inspector

`Tutor Debug Inspector` 只在 Debug 构建中可用。通过菜单栏的 `Tutor Debug…` 打开，选择 `Request Inspector`。

Inspector 为每一次 Tutor 请求生成形如 `TUTOR-yyyyMMdd-HHmmss-0001` 的内存追踪 ID，并按以下顺序展示：

1. Source Context 与 Raw AX Snapshot
2. Normalized Text
3. Context Diff（Previous / Current / Added / Removed / Stable）
4. Semantic Buffer（Before / Incoming / After / Commit）
5. Current Tutor Input
6. Prompt Assembly（System / Constraints / History / Current User）
7. Final API Request（脱敏 JSON body）
8. AI Response 与 latency 时间点

## 两条实际输入路径

持续跟随路径：

```text
AXLiveMonitor → ContextRevisionPipeline → TextNormalizer → ContextDiffEngine
→ SemanticBuffer → CurrentExplainableContentProvider
```

用户点击“解释当前内容”时，生产路径会重新读取当前窗口：

```text
AccessibilitySnapshotController.resolveSnapshot
→ CurrentExplainableContentProvider.receiveCurrentSnapshot
→ TutorCoordinator → TutorPromptBuilder → ProductionTutorEngine
→ OpenAICompatibleProvider
```

第二条路径不会经过持续跟随的 Diff 与 Semantic Buffer。Inspector 会明确显示 `bypassed · direct manual chunk`，不会伪造不存在的阶段。

## Current Turn Only

开启后，`PromptPackage` 会剔除 Tutor 历史正文，Provider 只接收 system 与当前 user 消息。当前生产架构本身没有保存 Tutor 正文历史，因此 Normal Context 下的 History 默认也为空；该开关用于后续 A/B 排查和防止未来引入 history 时失去隔离能力。

## 隐私边界

- 最多保留 12 次 Trace，仅存在当前进程内存中。
- 不写文件、不上传、不增加 Analytics。
- 只捕获 HTTP JSON body；不捕获 HTTP headers。
- API Key、Authorization、Bearer Token 与 Keychain 内容不会进入 Trace。
- 开发者可随时点击“清空内存 Trace”。
