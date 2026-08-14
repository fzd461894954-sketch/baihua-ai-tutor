# Custom Pet V1 架构

> 文档状态：STEP 1.7
> 更新日期：2026-08-14
> 当前范围：用户导入单张静态 PNG，预览后设为桌面老师

## 1. 边界

Custom Pet 是现有 PetKit 的资产导入与本地角色管理层。它不建立第二套窗口、状态机或动画系统，也不读取其他 App、访问网络或申请隐私权限。

V1 只支持单帧 PNG。以下能力不在本阶段：GIF、APNG、WebP、SVG、Sprite Sheet、Live2D、自动抠图、AI 生成、商城、账号和云同步。

## 2. 导入流水线

```text
NSOpenPanel 选择单个 PNG
          ↓
PetImageValidator
  文件 / PNG 签名 / 解码 / 单帧 / 尺寸 / Alpha
          ↓
PreparedPetImport
  缩小预览、默认名字、透明背景与大图提示
          ↓
用户预览
  浅色/深色背景、名字、70%～140% 桌面大小
          ↓
PetImporter
  创建 sRGB 优化副本、256 px 缩略图、manifest
          ↓
PetLibraryStore
  原子写入 index，保存当前角色
          ↓
PetLibrary.currentPet
          ↓
PetWindowController.reloadPet
          ↓
恢复当前 PetState 的通用动画
```

选择文件后不会立即替换桌面角色。只有用户在预览中点击“使用这个角色”，导入事务和 Library index 都成功后，当前角色才改变。

## 3. 数据模型

`PetModel` 是官方角色和用户角色的统一模型：

```text
id
name
source            bundled / userImported
type              staticImage
assetLocation
createdAt
scale
```

官方角色 ID 固定为 `official_flower_bunny`。用户角色 ID 由程序生成，格式为 `user_<UUID>`。状态层只接触 `PetState`，不知道 `PetSource`。

## 4. 本地存储

存储根目录通过 `FileManager` 的 `.applicationSupportDirectory` API 获取，正常 App bundle 下为：

```text
~/Library/Application Support/com.baihuaai.AITutorMac/Pets/
├── index.json
└── user_<UUID>/
    ├── manifest.json
    ├── pet.png
    └── thumbnail.png
```

- `pet.png`：最长边不超过 2048 px 的内部 sRGB 副本，保留 Alpha。
- `thumbnail.png`：最长边不超过 256 px，角色列表只读取缩略图。
- `manifest.json`：单个角色的可恢复元数据。
- `index.json`：角色 ID 顺序和当前角色 ID。

Manifest schema version 为 1，保存 `id/name/source/assetType/imageFile/createdAt/scale`。它不保存用户源文件路径、用户名或其他隐私信息。

## 5. 验证与优化

导入源文件必须满足：

- 文件存在且扩展名为 `.png`。
- 文件头是 PNG signature，ImageIO 类型也必须符合 PNG。
- 可以解码并且只有一帧；APNG 不作为静态图悄悄导入。
- 宽和高均至少 128 px。
- 单边不超过 16,000 px，总像素不超过 100,000,000；这是解码内存安全上限。

实际透明像素通过缩小后的 RGBA 像素扫描判断。完全不透明的 PNG 不拒绝，但预览必须提示可能看到矩形背景，并允许用户重新选择或继续使用。

超过 2048 px 的图片在预览中显示优化提示。导入统一生成内部 sRGB 副本；原始文件不会被修改、重命名、覆盖或删除。

## 6. 文件安全与事务

- 存储目录只接受程序生成并通过 UUID 校验的 ID。
- 用户原始文件名不用于目录或内部文件名，避免重名和路径穿越。
- 优化结果先写入 Pet Library 下的临时目录；图片、缩略图和 manifest 全部成功后才移动到最终目录。
- Library index 使用原子写入。index 写入失败时，新导入目录会回滚，用户源 PNG 保持不变。
- 日志只记录程序生成的角色 ID 和错误类别，不记录源文件路径。

## 7. 当前角色与窗口刷新

```text
PetLibrary
    ↓ currentPet change
PetWindowController
    ↓ stop current CAAnimation
replace PetView image in the same NSPanel
    ↓
PetStateController.start(currentState)
    ↓
PetAnimationController
```

刷新不会重建 `AppContainer`、Tutor Panel、热键或 `PetStateController`。Pet 的屏幕位置、显示/隐藏偏好和每个角色保存的缩放值继续使用现有机制。切换发生在 `thinking`、`warning` 等状态时，新图片继续渲染同一个状态。

用户静态 PNG 自动继承八种状态：Idle、Watching、Thinking、Speaking、Needs Input、Warning、Success 和 Error。动画仍是通用 Core Animation transform/opacity，不按官方或用户角色分支。

## 8. Fallback 与删除

`official_flower_bunny` 永远在内存角色列表首位，不能删除。启动时会逐个验证用户 manifest 和内部 PNG：manifest 损坏、文件丢失、PNG 无法解码或 current ID 无效时，从 index 移除无效项并回退花花老师。

删除只允许 `userImported`。删除当前用户角色时，顺序是：

1. 将 current ID 持久化为官方角色。
2. 让同一个 Pet Window 立即切回花花老师。
3. 删除 App Support 中的用户角色副本。
4. 更新 Library index。

删除确认明确说明不会删除用户原来的 PNG。

## 9. 性能与生命周期

- 列表使用 256 px 缩略图和 `NSCache`，不在滚动时反复解码原始大图。
- 桌面 Pet 使用最长边最多 2048 px 的内部图，不长期解码 8000 px 级源文件。
- 图片验证和优化从管理窗口的用户操作触发，SwiftUI 通过后台 Task 执行。
- 管理窗口关闭后没有 Timer、DisplayLink、网络任务或持续图片处理。
- Pet 动画仍使用可移除的 Core Animation，Idle CPU 特性与 STEP 1.6 一致。

## 10. 隐私与权限

导入完全在本机完成，不上传图片，不访问原文件所在目录以外的内容。唯一文件入口是用户主动操作的 `NSOpenPanel`。

STEP 1.7 不申请 Accessibility、Screen Recording、Microphone、Camera、Photos 或 Full Disk Access。Reduce Motion 继续只读取公开的系统显示偏好。

## 11. 未来扩展

未来动画 Pet 可以在 `PetAssetType` 和资产渲染层增加 Sprite/Layered 类型，把每个 `PetState` 映射到资源动画。`PetStateController`、Tutor 事件入口和当前状态集合不需要改变。V1 manifest 的 `schemaVersion` 为迁移保留版本边界。
