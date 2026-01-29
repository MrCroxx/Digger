# 翻译弹窗尺寸自适应与滚动

本文档说明本次 session 里为 Force Click 翻译弹窗实现的两类改进：
1) 当文本过长时优先横向扩展窗口，避免只纵向增长。
2) 当内容超过最大高度时启用滚动，窗口内可上下滚动浏览。
3) 当文本很短时，弹窗仍保证顶部模型名完整显示。
同时将 UI 文案集中到独立文件，便于未来做 i18n。

## 行为概览

- **宽度优先扩展**：在不超过屏幕可视区域与用户配置上限的前提下，逐步增大弹窗宽度以降低高度。
- **高度上限与滚动**：内容高度超过最大高度时，弹窗高度被限制，滚动条出现；未超过时无滚动条。
- **滚动条遮挡规避**：滚动条为 overlay 样式，并在需要滚动时为内容增加右侧留白，避免末尾字符被遮挡。
- **实时布局刷新**：Preferences 中修改最大宽高后，已显示的弹窗会即时重新布局。
- **模型名完整显示**：即使选择的文本很短，也会为顶部模型名+右侧按钮预留足够宽度。

## 实现要点

### 1) 基于文本测量的宽高计算

在 `ForceClickSelectionPopup.layoutContent(...)` 中对原文/译文/加载态文本进行测量：

- 先用基础宽度（`baseMaxWidth`）计算内容高度。
- 如果高度超过上限，按固定步进增大宽度（`widthStep`），直到高度满足约束或达到最大宽度。
- 超过最大高度仍无法满足时，启用滚动模式。

### 2) 滚动容器结构

弹窗的内容层级调整为：

- `contentView`（窗口可视范围）
  - `scrollView`（可滚动容器）
    - `documentView`（真实内容高度）

当内容高度超过上限时：

- `documentView.height` > `scrollView.height`
- `scrollView.hasVerticalScroller = true`
- `scrollView.scrollerStyle = .overlay`
- 额外的 `paddingRight` 留出滚动条空间

### 3) 最大宽高配置

新增偏好设置：

- `POPUP_MAX_WIDTH`
- `POPUP_MAX_HEIGHT`

逻辑遵循：

- 先读取用户配置。
- 再与屏幕可视区域进行裁剪（防止超出屏幕）。
- 只有内容超过最大高度时才展示滚动条。

### 4) UI 文案集中管理

新增 `UIStrings`，将所有 UI/UX 文案集中到 `Sources/digger/UIStrings.swift`，避免在业务逻辑中硬编码字符串，便于后续 i18n。

### 5) 模型名最小宽度保障

在 `ForceClickSelectionPopup.layoutContent(...)` 中新增 header 的最小宽度约束，避免模型名在短文本场景被截断：

- 读取 `AppPreferences.model()` 作为模型名。
- 使用 `NSTextField` 的实际字体测量模型名宽度，并额外考虑 label 内部留白。
- 计算 header 右侧按钮占用宽度（按钮数、按钮尺寸、间距）。
- 将 `headerMinWidth` 作为窗口最小宽度要求，并在屏幕可视范围内应用。

这样即便内容很短，弹窗也会扩展到足够容纳“模型名 + 按钮区”。

## 关键文件

- `Sources/digger/digger.swift`
  - 弹窗布局与滚动逻辑
  - Preferences 新增最大宽高配置
- `Sources/digger/UI/ForceClickSelectionPopup.swift`
  - header 最小宽度计算与模型名显示保障
- `Sources/digger/UIStrings.swift`
  - UI 文案集中管理

## 相关偏好设置键

- `PopupMaxWidth`（默认 520）
- `PopupMaxHeight`（默认 360）

## 交互说明

- 弹窗内滚轮/触控板可上下滚动。
- 弹窗仍支持拖动（背景拖动窗口）。
- 当滚动条不出现时，内容完整展示，无额外留白。
