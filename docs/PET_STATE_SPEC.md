# Pet State Specification

> 版本：STEP 1.6  
> 更新日期：2026-08-14  
> 适用资产：Static Pet V1 通用程序动画

## 1. 状态表

| State | 中文 | 含义 | 通用动画 | Badge | 自动 Bubble | 自动转换 | 未来触发 |
|---|---|---|---|---|---|---|---|
| `idle` | 待机 | 当前没有任务 | 3.2s 的 1.00↔1.015 呼吸，Y 不超过 1.5pt | 无 | 无 | 无 | 无任务、重置 |
| `watching` | 正在观察 | 注意到新的可见内容 | 慢速向一侧倾斜 1.5°，X 移动 1.5pt | `eye.fill` | 无 | 无 | AI 可见内容变化 |
| `thinking` | 正在理解 | 正在分析内容 | -2° → +2° → 0°，2s | `ellipsis` | 无 | 无 | Tutor 开始分析 |
| `speaking` | 正在解释 | 正在向用户解释 | 1.00↔1.01，1.35s | `waveform` | 无 | 无 | Tutor/TTS 开始输出 |
| `needsInput` | 等待你的操作 | 轮到用户决定或输入 | 进入时向上轻弹一次 | `questionmark.circle.fill` | “这里需要你操作一下。” | 无 | 需要用户确认/输入 |
| `warning` | 需要注意 | 存在需要关注的风险，不等于失败 | X ±3pt 的一次小幅 shake，0.36s | `exclamationmark.triangle.fill` | “这一步需要你注意。” | 无 | 风险下限要求关注 |
| `success` | 已完成 | 当前任务或阶段完成 | Y +8pt 与 scale 1.04 的一次轻弹 | `checkmark.circle.fill` | “完成啦。” | 约 1.8s 后回 `idle` | 任务/阶段成功 |
| `error` | 出现问题 | 刚才这一步失败 | Y -3pt 与 ±1.4° 的一次下沉摆动 | `xmark.circle.fill` | “刚才这一步没有成功。” | 无 | 执行或解释失败 |

## 2. Persistent 与 Transient

Persistent State：

```text
idle, watching, thinking, speaking,
needsInput, warning, error
```

上述状态只能由明确事件离开，状态机不根据时间自行推测。

Transient State：

```text
success → idle
```

未来可以扩展为 `success → previous stable state`，STEP 1.6 严格按需求回到 Idle。

## 3. 点击规则

| State | 单击 | 双击 |
|---|---|---|
| Idle | 原有欢迎 Bubble | 打开 Tutor Panel |
| Watching / Thinking | “我正在理解当前内容。” | 打开 Tutor Panel |
| Speaking | “我正在给你解释。” | 打开 Tutor Panel |
| Needs Input | 打开 Tutor Panel | 打开 Tutor Panel |
| Warning | 打开 Tutor Panel | 打开 Tutor Panel |
| Success | “完成啦。” | 打开 Tutor Panel |
| Error | 打开 Tutor Panel | 打开 Tutor Panel |

## 4. 转换不变式

每次状态转换都必须满足：

1. 取消上一 transient completion Task。
2. 移除上一状态的全部 Core Animation。
3. 恢复 `transform = identity` 和 `opacity = 1`。
4. 清理上一 Bubble 及自动隐藏 Task。
5. 更新唯一 `currentState`。
6. 启动新状态的通用动画和必要 Bubble。

同一时间只允许一组 State CAAnimation。Hover 或 Drag 可以暂停这组动画，但不改变 `currentState`。

## 5. Reduce Motion

开启 macOS Reduce Motion 后，循环平移、浮动、旋转、shake 和 bounce 不运行。Badge 和 Bubble 仍完整表达状态；需要入场反馈时只使用一次 0.45～0.5s 的轻微 opacity pulse。

## 6. 严格边界

STEP 1.6 中所有状态都由 Debug 菜单或测试人工切换。状态名和文案不声称已读取 ChatGPT、Codex、数据库、密钥或任何用户上下文。
