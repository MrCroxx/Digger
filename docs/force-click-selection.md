# Force Click 文本获取方案

本文档说明 `digger` 在触发 Force Click 后，如何获取当前选中的文本；当没有选中文本时，如何选中当前位置单词并输出到终端。

入口实现位于 `Sources/digger/digger.swift`。

## 目标与约束

- **优先获取用户已选中的文本**，尽量不改变用户状态。
- **无选中时自动选词**，行为尽量接近系统字典的默认体验。
- **支持 Chrome 等可访问性树不稳定的应用**，需要有兜底方案。
- **不污染剪贴板**，复制兜底时恢复用户原剪贴板内容。
- **已有选区时尽量保留选区**，避免 Force Click 前被清空。

## 总体流程

触发 Force Click 后的文本获取分为三层：

1. **聚焦元素直接读选中文本**：通过 AX 读取 `kAXSelectedTextAttribute`。
2. **选中范围 → 计算当前词**：没有选中文本时，根据插入点范围选中当前词并读取。
3. **剪贴板兜底**：若 AX 获取失败（Chrome 常见），使用 Cmd+C 复制选区；无选区则双击选词后复制。

另外，当鼠标按下时检测到已有选区，会缓存选区范围与文本；如果 Force Click 触发时选区已被清空，则尝试恢复选区并优先使用缓存文本。

## 详细实现

### 1) AX 读取当前选区

从系统级可访问性对象中获取当前聚焦元素：

```swift
guard let focusedElementValue = copyAttribute(
    element: systemElement,
    attribute: kAXFocusedUIElementAttribute as CFString
) else {
    return nil
}
let focusedElement = focusedElementValue as! AXUIElement
```

然后直接读取 `kAXSelectedTextAttribute`：

```swift
if let selectedText = copyAttribute(
    element: focusedElement,
    attribute: kAXSelectedTextAttribute as CFString
) as? String, !selectedText.isEmpty {
    return selectedText
}
```

如果聚焦元素没有选区，会继续尝试向下遍历可访问性树以寻找选区（对复杂控件有效）：

```swift
if let selectedText = findSelectedText(in: focusedElement, maxDepth: 4, remainingNodes: &remainingNodes) {
    return selectedText
}
```

### 2) 无选区时选中当前词

当 `kAXSelectedTextAttribute` 为空时，读取插入点范围 `kAXSelectedTextRangeAttribute`，计算当前词并设置新的选区：

```swift
guard let rangeValueAny = copyAttribute(
    element: focusedElement,
    attribute: kAXSelectedTextRangeAttribute as CFString
) else {
    return nil
}

var selectionRange = CFRange()
AXValueGetValue(rangeValue, .cfRange, &selectionRange)
```

为了计算“当前词”，优先使用 `kAXValueAttribute` 读取完整文本；如果完整文本不可用，则使用 `kAXVisibleCharacterRangeAttribute` + `kAXStringForRangeParameterizedAttribute` 获取可见文本作为上下文：

```swift
if let fullText = copyAttribute(
    element: focusedElement,
    attribute: kAXValueAttribute as CFString
) as? String { ... }
else if let visibleRangeValue = copyAttribute(
    element: focusedElement,
    attribute: kAXVisibleCharacterRangeAttribute as CFString
) { ... }
```

随后用 `CFStringTokenizer` 在上下文文本中定位词边界，并设置新的选区：

```swift
let wordRange = currentWordRange(in: contextText, caretIndex: caretIndex)
var adjustedRange = CFRange(location: contextBaseLocation + wordRange.location, length: wordRange.length)
let axRange = AXValueCreate(.cfRange, &adjustedRange)
AXUIElementSetAttributeValue(
    focusedElement,
    kAXSelectedTextRangeAttribute as CFString,
    axRange
)
```

### 3) 剪贴板兜底（Chrome 等）

Chrome 经常不返回 `kAXSelectedTextAttribute`，也不提供稳定的 `kAXValueAttribute`。因此加了复制兜底：

1. 发送 Cmd+C，读取 `NSPasteboard.general` 获取文本。
2. 如果剪贴板没有变化或为空，则在鼠标位置双击选词，再次 Cmd+C。
3. 复制完成后恢复原剪贴板内容。

```swift
let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
sendCopyCommand()
Thread.sleep(forTimeInterval: 0.08)
var copiedText = pasteboard.string(forType: .string)

if copiedText?.isEmpty ?? true {
    performDoubleClick(at: location)
    Thread.sleep(forTimeInterval: 0.06)
    sendCopyCommand()
    Thread.sleep(forTimeInterval: 0.08)
    copiedText = pasteboard.string(forType: .string)
}

snapshot.restore(to: pasteboard)
```

事件注入采用 `.cgSessionEventTap`，避免被自身的 HID event tap 抑制：

```swift
keyDown?.post(tap: .cgSessionEventTap)
keyUp?.post(tap: .cgSessionEventTap)
```

## 权限与行为说明

- **Accessibility 权限**：AX 读取和事件注入都依赖该权限。
- **剪贴板恢复**：复制兜底会暂时修改剪贴板，但会完整恢复原数据。
- **Chrome 行为**：通常会走剪贴板兜底路径。

## 相关代码位置

- `Sources/digger/digger.swift`：`ForceClickSelectionHandler`、`findSelectedText`、`PasteboardSnapshot`
