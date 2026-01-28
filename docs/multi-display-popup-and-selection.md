# 多显示器弹窗定位与 Force Click 选词

本文档记录本次 session 修复的两个问题，并解释实现原理与关键细节：

- 弹窗在内置屏可见，但外接显示器不可见。
- 未选中任何文本时 Force Click 会导致鼠标位置“跳动”。

实现集中在 `Sources/digger/digger.swift`。

## 问题一：外接显示器看不到弹窗

### 现象

在 MacBook 内置显示器上弹窗显示正常，但当鼠标位于外接显示器时，弹窗经常出现在不可见区域或跨屏位置，导致“看不到”。

### 原因

AppKit 的 `NSEvent.mouseLocation` 返回的是全局屏幕坐标（主屏坐标系），但弹窗显示位置没有进行屏幕边界约束。多屏环境下，屏幕坐标系可能跨越主屏原点，导致弹窗落在屏幕之外或被截断。

### 修复方案

1. 仍使用 AppKit 的全局坐标作为显示基准。
2. 在弹窗显示前，将目标位置钳制到鼠标所在屏幕的 `visibleFrame`（排除 Dock/菜单栏区域）。

核心逻辑：

```swift
let clampedOrigin = clampOrigin(origin, for: frame.size, near: location)
window.setFrameOrigin(clampedOrigin)
```

`clampOrigin` 做了两件事：

- 根据鼠标位置找到对应屏幕。
- 按 `visibleFrame` 边界裁剪弹窗坐标，保留最小 padding，保证弹窗不越界。

### 关键点

- **坐标基准一致**：弹窗定位依赖 AppKit 坐标（`NSEvent.mouseLocation`）。
- **屏幕边界约束**：避免窗口位置超出外接显示器边缘。
- **可视区域**：使用 `visibleFrame` 规避 Dock/菜单栏遮挡。

## 问题二：Force Click 选词时鼠标位置被移动

### 现象

当没有任何选区时触发 Force Click，会进行双击选词以模拟 macOS 行为，但鼠标位置会出现轻微跳动或偏移。

### 原因

Force Click 触发后，选词流程会执行模拟双击：

```swift
performDoubleClick(at: location)
```

之前 `location` 来源于 `NSEvent.mouseLocation`（AppKit 全局坐标）。
而 `CGEvent` 模拟鼠标事件使用的是 Quartz 坐标系；在多屏或缩放环境下，两者可能出现偏差，导致模拟点击位置与真实光标位置不一致，产生“跳动”。

### 修复方案

在模拟双击时优先使用 Quartz 事件坐标：

```swift
if let location = currentEventTapMouseLocation() ?? currentMouseLocation() {
    performDoubleClick(at: location)
}
```

其中 `currentEventTapMouseLocation()` 使用：

```swift
CGEvent(source: nil)?.location
```

这样可以保证 **模拟事件与事件坐标同源**，避免跨坐标系误差。

### 关键点

- **模拟事件坐标统一**：模拟点击使用 `CGEvent` 的坐标。
- **回退机制**：当无法获得 `CGEvent` 坐标时，回退到 `NSEvent.mouseLocation`。
- **默认行为一致**：无选区时 Force Click 选中光标处的单词，符合 macOS 默认交互。

## 相关代码位置

- `Sources/digger/digger.swift`：
  - `ForceClickSelectionPopup.show(original:translation:near:)`
  - `ForceClickSelectionPopup.clampOrigin(_:for:near:)`
  - `ForceClickSelectionHandler.copySelectionText(selectWordIfNeeded:)`
  - `ForceClickSelectionHandler.currentEventTapMouseLocation()`

## 行为总结

- 多显示器环境下弹窗位置始终可见。
- 无选中状态下 Force Click 选词不会导致鼠标跳动。
- 弹窗显示与模拟点击各自使用最合适的坐标系统，避免互相干扰。
