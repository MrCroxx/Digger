# 弹窗右上角按钮与提示说明

本文档记录本次 session 在弹窗右上角新增操作按钮与自定义提示的实现方式、关键逻辑与配置项，便于维护与扩展。

## 目标概述

- 在弹窗右上角新增一排按钮：复制译文、复制原文+译文、打开偏好设置
- 复制内容写入系统剪贴板
- 提示文字支持 i18n，并支持可配置的延迟显示
- 提示窗口大小与字体自适应，避免裁切或省略

## UI 结构与布局

弹窗拆分为两层：

- header 区域：仅包含按钮（固定不随内容滚动）
- content 区域：原文/译文等正文内容（可滚动）

实现上在 `ForceClickSelectionPopup` 内新增 `headerView`，并将三枚按钮作为其子视图。滚动区域仍使用 `scrollView`，并在布局时为 header 预留高度。

涉及文件：

- `Sources/digger/UI/ForceClickSelectionPopup.swift`

## 按钮行为与复制逻辑

### 1) 复制译文

复制 `translationTextField` 的内容（去除首尾空白）。如果译文为空则按钮置灰，并禁止复制。

### 2) 复制原文 + 译文

复制格式为：

```
原文

译文
```

同样在译文为空时禁用按钮。

### 3) 打开偏好设置

按钮触发 `ForceClickSelectionPopup.onOpenPreferences` 回调，由 `App/Digger.swift` 中绑定到 `PreferencesWindowController.show()`。

涉及文件：

- `Sources/digger/UI/ForceClickSelectionPopup.swift`
- `Sources/digger/App/Digger.swift`

## 自定义提示实现

系统 tooltip 无法按需控制延迟，因此改为自定义提示窗口：

- `HoverableIconButton`：自定义按钮，提供 hover 事件回调
- `HoverTooltipWindow`：自绘提示窗口

### 触发流程

1. 鼠标进入按钮区域 -> 启动定时器
2. 延迟达到配置值后显示自定义提示窗口
3. 鼠标离开或按钮被点击 -> 取消/隐藏提示

### 提示尺寸与字体适配

- 提示文字使用测量后的 `boundingRect` 计算宽高
- 支持多行换行，避免截断
- 提示字体大小随弹窗字体比例变化（基于 `PopupFontPreferences`）

涉及文件：

- `Sources/digger/UI/ForceClickSelectionPopup.swift`

## i18n 文案

新增的按钮提示文本通过 `UIStrings` 管理：

- `popupCopyTranslation`
- `popupCopyAll`
- `popupOpenPreferences`
- `preferencesPopupTooltipDelayLabel`

涉及文件：

- `Sources/digger/UIStrings.swift`

## 偏好设置新增项

新增提示延迟配置：

- key: `PopupTooltipDelayMs`
- 默认值：`300`
- 允许设置为 `0`（立即显示）

偏好设置 UI 增加输入项，支持多语言标签。

涉及文件：

- `Sources/digger/Preferences/AppPreferences.swift`
- `Sources/digger/Preferences/PreferencesWindowController.swift`

## 关键文件索引

- `Sources/digger/UI/ForceClickSelectionPopup.swift`
  - header 区域与按钮
  - 复制逻辑
  - hover 提示逻辑
- `Sources/digger/Preferences/AppPreferences.swift`
  - `popupTooltipDelayMs()` / `setPopupTooltipDelayMs(_:)`
- `Sources/digger/Preferences/PreferencesWindowController.swift`
  - 提示延迟的 UI 配置
- `Sources/digger/UIStrings.swift`
  - 按钮提示与偏好设置文案

## 可扩展方向

- 提示窗口加入最大宽度与自动定位（避免靠近屏幕边缘时遮挡）
- 按钮可加入快捷键或状态反馈（例如复制成功提示）
