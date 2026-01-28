# Force Click 选区缓存与恢复

本文档说明 `digger` 在 Force Click 触发前后如何缓存已有选区、在选区被清空时恢复选区，并保证“无选区时仍按系统默认选词行为”不受影响。

入口实现位于 `Sources/digger/digger.swift`。

## 背景问题

很多应用在 `mouseDown` 时会清空已有选区（文本编辑器、网页输入框、部分 PDF 阅读器等）。
Force Click 的判定发生在按下之后，因此常见现象是：触发时选区已经被应用清空，导致无法读取原选区。

## 目标与约束

- **已有选区时尽量保留**：在 `mouseDown` 前缓存选区；触发时恢复并优先使用缓存文本。
- **无选区不改变行为**：没有选区时仍保持“选取光标位置单词”的默认路径。
- **低侵入**：只在检测到已有选区时介入；不干扰正常点击或拖拽。

## 总体流程

1. **mouseDown**：检测是否存在选区，若有则缓存选区范围与文本。
2. **Force Click 触发**：若当前无选区但缓存存在且有效，先恢复选区并使用缓存文本。
3. **无缓存或恢复失败**：回落到既有的“选区/选词/剪贴板兜底”流程。

## 关键实现

### 1) 缓存选区（仅在已有选区时）

- 在 `EventTapController` 里拦截 `leftMouseDown`，调用 `cacheSelectionBeforeMouseDown()`。
- 仅当存在 **非空选区** 时保存 `AX` 选区范围与文本。
- 缓存带有时间戳，用于控制短时有效。

```swift
func cacheSelectionBeforeMouseDown() {
    guard let snapshot = captureSelectionSnapshot() else {
        selectionCacheLock.withLockUnchecked { $0 = nil }
        return
    }
    selectionCacheLock.withLockUnchecked { $0 = snapshot }
}
```

### 2) Force Click 时恢复选区并优先使用缓存文本

- Force Click 触发后先尝试读取当前选区。
- 若当前选区为空但缓存有效，则恢复选区范围并优先使用缓存文本。
- 恢复成功后避免再触发“无选区选词”的逻辑，保证行为稳定。

```swift
if let cachedSelection = consumeSelectionSnapshotIfValid() {
    _ = restoreSelection(cachedSelection)
    var cachedText = cachedSelection.text
    if cachedText.isEmpty {
        cachedText = copySelectionText(selectWordIfNeeded: false) ?? ""
    }
    if !cachedText.isEmpty {
        print(cachedText)
        translateAndShow(text: cachedText)
        return
    }
}
```

### 3) 无选区时保持默认选词行为

- 如果没有缓存或缓存不可用，继续走原有路径：
  - `AX` 读取插入点，计算当前词并选中
  - `AX` 不稳定时，走剪贴板兜底（必要时双击选词）

```swift
guard let text = fetchOrSelectText(), !text.isEmpty else {
    if let fallbackText = copySelectionText(selectWordIfNeeded: shouldSelectWordFallback()),
       !fallbackText.isEmpty {
        print(fallbackText)
        translateAndShow(text: fallbackText)
    }
    return
}
```

### 4) 兜底策略更保守

在无法读取 `kAXSelectedTextRangeAttribute` 时，
`shouldSelectWordFallback()` 会返回 `true`，确保“无选区选词”不会中断。

```swift
guard let rangeValueAny = copyAttribute(
    element: focusedElement,
    attribute: kAXSelectedTextRangeAttribute as CFString
) else {
    return true
}
```

### 5) 缓存生命周期与清理

- 缓存带 TTL（目前为 0.8s），避免陈旧选区误恢复。
- `leftMouseUp` 时清空缓存，避免影响后续点击。

```swift
case .leftMouseUp:
    monitor.setMouseDown(false)
    selectionHandler.clearSelectionCache()
```

## 行为总结

- **已有选区**：Force Click 触发时尽量恢复原选区并使用缓存文本。
- **无选区**：保持原有的“选取光标位置单词”逻辑，不改变系统默认交互。
- **不可读选区**：仍会触发双击选词兜底，避免“什么都没发生”。

## 相关代码位置

- `Sources/digger/digger.swift`：
  - `ForceClickSelectionHandler`（缓存、恢复与主流程）
  - `EventTapController`（mouseDown/mouseUp 缓存触发）
