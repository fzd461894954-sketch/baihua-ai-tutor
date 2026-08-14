# Pet 资产规范

> 文档状态：STEP 1.6  
> 更新日期：2026-08-14

## 1. 当前官方资产状态

```text
Official Pet transparent asset: READY
Asset slot: official_flower_bunny
Current runtime: official transparent PNG
```

用户在 STEP 1.6 提供的正式透明 PNG 已放入 `official_flower_bunny.imageset`，并在不改变角色像素设计的前提下补入 sRGB IEC61966-2.1 色彩配置。

```text
Filename: official_flower_bunny.png
Dimensions: 1254 × 1254 px
Format: 8-bit RGBA PNG
Alpha: YES
Profile: sRGB IEC61966-2.1
```

`PetModel.officialFlowerBunny.assetName` 仍为 `official_flower_bunny`。资产缺失时的占位逻辑保留作为异常保护，正常运行不再显示占位符。

不对现有绿色背景设计图做简单 Chroma Key。角色自身含绿色花瓣，按颜色删除背景会伤害官方形象。

## 2. 官方角色不可改变的设计

正式资产必须保留已有设计，不重新设计：

- 彩虹花瓣轮廓
- 白色兔耳
- 米白色头套
- 红色四瓣嘴
- 蓝色星星裙
- 花朵斜挎包
- 原有整体比例
- 原有玩偶质感

交付应来自原设计的高质量分层导出或专业 Alpha 抠图，不是重新生成一个相似角色。

## 3. Static Pet V1

推荐规范：

| 项目 | 要求 |
|---|---|
| 格式 | PNG（首选），必须带 Alpha 透明通道 |
| 色彩 | sRGB |
| 背景 | 完全透明，无绿幕、白底、棋盘格或假透明 |
| 画布 | 尽量紧贴角色外轮廓，只留必要的柔边/阴影空间 |
| 像素高度 | 建议 1024～2048 px，不强制必须 2048 px |
| 构图 | 保留完整角色，不裁耳朵、花瓣、裙摆或斜挎包 |
| 命名 | `official_flower_bunny.png` |

不推荐 JPG/JPEG，因为它没有 Alpha 通道。STEP 1.5 的资产槽使用 Xcode Image Set，程序会自动按窗口尺寸等比缩放，因此不会把 2048 px 作为硬性门槛。

## 4. 交付和验证清单

替换占位符时：

1. 将透明 PNG 放入 `AITutorMac/AITutorMac/Pet/Resources/Assets.xcassets/official_flower_bunny.imageset` 并在 `Contents.json` 指定 filename。
2. 保持 Image Set 名称为 `official_flower_bunny`，不需要修改 `PetView`。
3. 在深色、浅色和多种桌面背景上检查边缘，不应有绿边、白边或锋齿。
4. 检查画布空白；透明区不应导致大面积桌面无法点击。
5. 在 70%、100%、140% 尺寸下检查清晰度和完整边界。
6. 本次已完成程序解码、Alpha、缩放和透明窗口检查；更多桌面颜色上的细微边缘观感仍可在最终视觉 QA 中继续核对。

## 5. 未来用户自定义 Pet 最小规范

`03_CUSTOM_PET` 的最小用户入口将是一张透明 PNG。导入后，软件可以为它自动提供：

- Idle breathing
- 轻微 floating
- Drag
- Hover
- Scale
- Generic Success bounce
- Generic Warning shake

未来导入层应检查：可解码、有效尺寸、有 Alpha、不超过合理文件/像素上限，并在本地安全保存。STEP 1.5 不开发导入、角色切换、WebP 解码策略、Sprite Sheet 或骨骼动画。

## 6. 透明点击区技术债

STEP 1.5 使用窗口边界点击。未来如果用户资产形状差异很大，可以在不改变 `PetModel → PetView` 入口的前提下，向交互层增加缓存后的 Alpha/Pixel Hit Testing。这不应在每次鼠标移动时重新解码整张图像。
