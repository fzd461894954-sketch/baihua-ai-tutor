# 白话 AI PetKit 架构

> 文档状态：STEP 1.6 基线  
> 更新日期：2026-08-14  
> 当前范围：桌面吉祥物窗口、基础交互、偏好、统一 PetState 与通用静态 Pet 动画

## 1. 边界

PetKit 是纯本地 UI 与交互模块。STEP 1.6 不读取其他 App，不发起网络请求，不使用 Accessibility、ScreenCaptureKit、OCR、麦克风、语音、Tutor Engine 或 AI Provider。它只读取 macOS 的 Reduce Motion 显示偏好；该 API 不请求 Accessibility 权限。

Tutor Panel 和 Pet Window 是两个独立窗口：

```text
AppContainer
├── FloatingPanelController    # 教学窗口
├── HotKeyManager             # Option + Space
├── PetStateController        # 状态真相源
└── PetWindowController       # 桌面吉祥物
```

`FloatingPanelController` 不管理 Pet。`PetWindowController` 只持有一个 `onOpenTutor` 回调，不知道 Tutor Engine、AI Provider 或上下文采集。

## 2. 核心流程

```text
AppContainer
      ↓
PetWindowController
      ↓
PetView
      ↓
PetModel.assetName
```

```text
Pet double click
      ↓
onOpenTutor
      ↓
FloatingPanelController.show()
```

`AppContainer` 是组装点。App 启动时先创建 Tutor Panel（保持隐藏），再启动 Pet。Pet 的显示偏好在首次启动默认为开；如果用户之前选择了隐藏，下次启动会尊重该偏好。

## 3. PetModel 与资产入口

`PetModel` 提供统一入口：

```swift
struct PetModel: Identifiable, Codable {
  let id: String
  let name: String
  let assetName: String
  let type: PetAssetType
}
```

STEP 1.6 仍只支持 `PetAssetType.staticImage`。官方配置是：

```text
id: official_flower_bunny
name: 花花老师
assetName: official_flower_bunny
```

`PetView` 从模型读取 `assetName`，不把官方名称写死在视图里。官方透明 PNG 已经放入资产槽并使用 sRGB 配置；资产缺失时的明确占位逻辑仍保留，没有绿幕自动抠图。

## 4. PetWindow

`PetWindowController` 创建独立的无边框 `NSPanel`：

- `isOpaque = false`
- `backgroundColor = .clear`
- 没有标题栏、红黄绿按钮和窗口背景
- `level = .floating`，不使用 `.screenSaver`
- 可加入所有 Spaces，并声明 `fullScreenAuxiliary`
- App 保持 `LSUIElement` / accessory 模式，不出现常驻 Dock 图标

单击气泡是另一个忽略鼠标事件的透明辅助 `NSPanel`。这样可以让 Pet 本体窗口紧贴角色，避免一块永久存在的大透明点击区。

## 5. 位置、拖拽与多屏

首次启动使用主屏 `visibleFrame` 计算右下位置，与 Dock、菜单栏和屏幕边缘保留 24 pt 余量。

拖拽由 AppKit 交互视图处理。鼠标按下时记录全局鼠标坐标与窗口原点，拖动时使用两者差值更新窗口；因此窗口自身移动不会导致手势坐标跳变。松开鼠标后位置写入 `UserDefaults`。

恢复位置时，只要窗口在某个当前 `visibleFrame` 中仍有可操作的可见面积就保留。如果保存位置已随外接显示器消失，会回到主屏右下。App 运行期的屏幕参数变化也会进行同样校验。

## 6. 偏好存储

`PetStore` 只使用 `UserDefaults` 保存非敏感 UI 偏好：

| Key | 用途 |
|---|---|
| `PetWindowPosition` | Pet 窗口原点 |
| `PetScale` | 用户缩放比例 |
| `PetVisible` | 用户是否选择显示 Pet |

缩放范围为 `0.7...1.4`，右键每次调整 10%。官方透明 PNG 是方形画布，默认窗口因此调整为 180 × 180 pt，让角色本体在等比缩放后仍保持约 150～190 pt 的桌面观感。

## 7. PetState 与状态机

`PetState` 是唯一状态集合：

```text
idle, watching, thinking, speaking,
needsInput, warning, success, error
```

`PetStateController` 是状态真相源。它不参与 View 布局，每次 `transition(to:)` 严格执行：

```text
1. prepareForStateTransition   # 停止旧动画/气泡，恢复 baseline
2. currentState = newState
3. OSLog 记录 state name
4. renderPetState             # 启动新动画/必要气泡
```

`idle / watching / thinking / speaking / needsInput / warning / error` 是 Persistent State，不会自行推测下一状态。`success` 是 Transient State，完成入场表现后通知状态机转回 `idle`。过期的 Success 完成回调在用户已切换到其他状态后不会覆盖新状态。

## 8. 统一动画生命周期

`PetAnimationController` 替代单独的 Idle Animator，但仍只使用通用 transform / opacity，完全不判断是否为官方角色。

```text
PetStateController
        ↓
PetWindowController (PetStateRendering)
        ↓
PetAnimationController
        ↓
Static Pet content layer
```

状态动画使用可移除的 Core Animation，不使用 Timer 或 DisplayLink。每次切换都取消 transient Task、移除全部 CAAnimation，并将 `transform = identity` / `opacity = 1`，所以倾斜、平移和缩放不累积。

鼠标 Hover 时暂停当前动画并轻微放大，Badge 仍然可见。拖动开始时恢复稳定 baseline，拖动结束后重新从当前状态启动，避免用户拖动的同时 Pet 自己摇晃。

## 9. Reduce Motion

`PetAnimationController` 读取 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`，并监听系统显示偏好变化。开启 Reduce Motion 后：

- Idle / Watching / Thinking / Speaking 保持静态，但 Badge 仍表达状态。
- Needs Input / Warning / Error 只使用一次轻微 opacity pulse。
- Success 使用轻微 opacity pulse，仍会自动返回 Idle。

读取 Reduce Motion 不是读取其他 App 的 Accessibility API，也不会触发权限请求。

## 10. Bubble 与点击

`PetBubble` 是通用气泡内容模型，欢迎、需要输入、警告、成功和错误共用同一透明辅助 Panel。Watching / Thinking / Speaking 改变时不自动弹气泡，避免打扰。任何新状态都会先清理上一气泡的自动隐藏 Task。

双击在任何状态下都只打开已有 Tutor Panel。Needs Input / Warning / Error 的单击也打开 Tutor Panel；其他状态显示与当前 Debug 状态匹配的通用本地文案。

## 11. Future Tutor Event Mapping

STEP 1.6 没有 Tutor Engine，但未来事件只需依赖 `PetStateController.transition(to:)`：

```text
AI 可见内容变化        → watching
Tutor 开始分析          → thinking
Tutor/TTS 开始解释     → speaking
需要用户确认            → needsInput
风险等级需要关注          → warning
任务/阶段完成           → success
执行或解释失败            → error
无任务/重置              → idle
```

事件生产者不调用 Core Animation，Pet View 也不根据 Tutor 字段自行推理状态。

## 12. 未来自定义 Pet

未来 `03_CUSTOM_PET` 可以将用户导入的透明静态图生成新 `PetModel`，仍复用同一套：

- 透明窗口
- 拖拽、位置恢复与多屏保护
- 缩放与显示偏好
- 通用呼吸/悬停动画
- 通用的成功弹跳与警告摇晃

`sprite`、`animated`、`userImported` 类型以后再在资产加载层增加；当前不引入 SpriteKit、Lottie、Rive、Live2D 或其他第三方框架。

Static Pet 继续使用通用程序动画。未来 Sprite Pet 可以将状态映射为帧动画，Layered Pet 可以映射到耳朵/嘴/手等独立部件；这些实现只需替换状态渲染器，不更改 `PetStateController` 的事件入口。

## 13. Debug State Controller

Debug 构建的菜单栏显示“吉祥物状态”和“开发测试 → Pet 状态”八个人工入口。Release 构建不编译该区块。Debug 还提供 `--pet-state=<rawValue>` 单状态视觉验收参数，以及 `--pet-state-stress-test` 启动参数；后者只用于本地自动轮换 30 次真实窗口状态并验证资源回落。

## 14. 已知限制

- STEP 1.5 先接受 Pet 窗口边界内的点击，没有像素级 Alpha Hit Testing。正式资产必须尽量紧贴角色边界，以减少透明区阻挡。
- `fullScreenAuxiliary` 已配置，但不同 macOS 版本、显示器与全屏 App 组合仍需要人工实测。
- 当前 PNG 是单层静态资产，所以 Speaking 不做嘴型，也不扭曲角色脸部。
