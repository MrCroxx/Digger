# 弹窗结果可选取与分区复制

本文档记录本次 session 为弹窗新增的交互能力：结果文本可选取、全局按钮与内容分隔、以及原文/每个处理区域的独立复制按钮。用于后续维护与扩展。

## 目标概述

- 处理结果可以被鼠标选取（含原文与各功能结果）
- 移除顶部“复制译文”按钮
- 在每个处理区域右上角提供复制按钮，用于复制该区域结果
- 原文区域右上角也提供复制按钮
- 顶部全局按钮与内容区域使用同样的分隔线隔开

## 关键实现点

### 1) 结果文本可选取，但不破坏拖拽

弹窗主体可拖拽，默认 `DraggableScrollView.mouseDown` 会直接触发窗口拖动。为了支持文本选取：

- 将原文与各处理结果 `NSTextField.isSelectable` 设为 `true`
- 在 `DraggableScrollView.mouseDown` 中判断点击位置是否命中可选文本，若是则交给 `super.mouseDown` 处理选取；否则保持拖拽窗口

实现位置：

- `Sources/digger/UI/ForceClickSelectionPopup.swift`

### 2) 原文与分区复制按钮

为原文与每个处理分区新增独立复制按钮，统一样式与 tooltip：

- 原文：`originalCopyButton`
- 分区：`FunctionSection.copyButton`

按钮与标题同行，靠右对齐。按钮启用状态根据对应文本是否为空及是否加载完成控制。

实现位置：

- `Sources/digger/UI/ForceClickSelectionPopup.swift`

### 3) 移除顶部“复制译文”按钮

顶部仅保留“复制全部/偏好设置”，避免与分区复制逻辑重复。

实现位置：

- `Sources/digger/UI/ForceClickSelectionPopup.swift`

### 4) 顶部区域分隔线

新增 `headerDividerView`，颜色使用系统 `separatorColor`，与内容区分隔线视觉一致。

实现位置：

- `Sources/digger/UI/ForceClickSelectionPopup.swift`

## UIStrings 文案

新增分区复制通用文案：

- `popupCopyResult`
- `popupCopyResultSuccess`

用于原文与分区复制按钮的 tooltip 与复制成功提示。

实现位置：

- `Sources/digger/UIStrings.swift`

## 关键文件索引

- `Sources/digger/UI/ForceClickSelectionPopup.swift`
  - 可选取文本 + 拖拽判定
  - 原文与分区复制按钮
  - 顶部分隔线
- `Sources/digger/UIStrings.swift`
  - `popupCopyResult` / `popupCopyResultSuccess`
