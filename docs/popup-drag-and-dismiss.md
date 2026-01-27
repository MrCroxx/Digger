# 弹窗拖动与点击关闭修复

本文档记录本次 session 对弹窗交互的新增功能与 bug 修复，包含实现思路与关键点。

## 目标

- 支持拖动弹窗移动位置。
- 修复点击弹窗自身会关闭的问题（尤其是拖动后再次点击）。
- 修复偶发的“最后一个字符被吞”显示问题。

## 改动概览

实现集中在 `Sources/digger/digger.swift`，主要涉及：

- 新增 `DraggableContentView`，让弹窗支持原生拖动。
- 调整点击关闭逻辑，使用系统命中测试判断点击是否落在弹窗上。
- 重新计算内容布局，避免右侧字符被裁切。

## 1) 拖动弹窗

### 1.1 可拖动的内容视图

为弹窗的 `contentView` 引入 `DraggableContentView`，并开启原生拖动逻辑。

```swift
private final class DraggableContentView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }
}
```

关键点：

- `mouseDownCanMoveWindow` 交给 AppKit 管理拖动位移，避免自行处理坐标带来的不一致。
- `acceptsFirstMouse` 保证首次点击即可拖动，不必先激活窗口。
- `hitTest` 返回自身，确保空白区域也可响应拖动。

### 1.2 Window 允许背景拖动

启用 `isMovableByWindowBackground`，让无边框窗口也能从背景拖动：

```swift
window.isMovableByWindowBackground = true
```

## 2) 修复拖动后点击即关闭

### 2.1 问题原因

原逻辑使用 `window.frame.contains(location)` 判断点击是否在弹窗内。拖动后，CGEventTap 获取的坐标与 AppKit 的窗口命中并不总是同步，导致“点击弹窗却被判定为外部”。

### 2.2 解决方案：系统命中测试

改为用系统的窗口命中测试（windowNumber-at-point），作为第一优先判断：

```swift
private func isLocationInsideWindow(_ location: CGPoint) -> Bool {
    let windowNumberAtPoint = NSWindow.windowNumber(
        at: location,
        belowWindowWithWindowNumber: 0
    )
    if windowNumberAtPoint == window.windowNumber {
        return true
    }
    if let contentView = window.contentView {
        let windowPoint = window.convertPoint(fromScreen: location)
        return contentView.bounds.contains(windowPoint)
    }
    return window.frame.contains(location)
}
```

判断顺序：

1. 系统命中测试返回的窗口号与当前弹窗一致 → 视为在窗口内。
2. 再退回到 `contentView` 坐标系判断。
3. 最后回退到 `window.frame` 判定。

这样即使拖动后坐标同步有偏差，也不会误判为“点击外部”。

## 3) 修复最后一个字符被吞

### 3.1 问题原因

`boundingRect` 计算的宽度可能略小于实际渲染宽度，导致右侧最后一个字符被裁切。

### 3.2 修复手段

增大额外留白，并让 `textField` 的宽度完整使用内容尺寸：

```swift
let extraSize = CGSize(width: 10, height: 2)
let textSize = CGSize(width: ceil(boundingRect.width) + 2, height: ceil(boundingRect.height))

let contentSize = CGSize(
    width: max(textSize.width + padding.width * 2 + extraSize.width, 60),
    height: max(textSize.height + padding.height * 2 + extraSize.height, 28)
)

textField.frame = NSRect(
    x: padding.width,
    y: padding.height,
    width: contentSize.width - padding.width * 2,
    height: contentSize.height - padding.height * 2
)
```

结果：文本区域可容纳内容，并提供额外右侧留白，避免裁切。

## 相关代码位置

- `Sources/digger/digger.swift`：`DraggableContentView`、`ForceClickSelectionPopup.layoutContent()`、`ForceClickSelectionPopup.dismissIfClickOutside()`
