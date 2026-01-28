# Force Click 翻译浮窗的加载态与扩展动画

本文档说明 `digger` 在 Force Click 触发后，如何立即显示包含原文的浮窗，并在翻译完成后扩展浮窗显示译文，同时提供加载动画来提升等待体验。

入口实现位于 `Sources/digger/digger.swift`。

## 目标与约束

- **即时反馈**：Force Click 后不等待翻译，立即显示原文。
- **平滑扩展**：译文返回后更新浮窗，并通过动画扩展尺寸。
- **加载提示**：翻译过程中显示文字动画，避免“无响应”错觉。
- **避免串单**：并发翻译时只更新最新请求的浮窗。

## 总体流程

1. 获取原文与鼠标位置。
2. 立即显示加载态浮窗，只包含原文 + 加载提示。
3. 异步请求翻译结果。
4. 翻译完成后更新浮窗，显示译文并扩展窗口尺寸。

## 关键实现

### 1) 立即显示加载态浮窗

Force Click 的处理逻辑中，先生成 `requestID`，再展示加载态浮窗：

```swift
let requestID = UUID()
Task { @MainActor in
    forceClickSelectionPopup.showLoading(original: trimmedText, near: location, requestID: requestID)
}
```

`showLoading` 会保存 `requestID`，并隐藏译文区域，只展示原文与加载文案。

### 2) 并发请求的防串单

翻译完成后回到主线程更新时，校验 `requestID` 是否仍为当前请求：

```swift
func updateTranslation(_ translation: String, for requestID: UUID, near location: CGPoint) {
    guard currentRequestID == requestID else {
        return
    }
    ...
}
```

这样可以避免用户连续多次 Force Click 时，旧请求覆盖新请求的浮窗内容。

### 3) 加载动画

加载动画使用 `Timer` 定时更新文字（例如“译文翻译中···”）：

```swift
loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
    Task { @MainActor in
        self?.tickLoadingAnimation()
    }
}
```

关键点：`ForceClickSelectionPopup` 运行在 `MainActor` 上，Timer 回调中通过 `Task { @MainActor ... }` 回到主线程，避免 actor 隔离警告。

### 4) 浮窗扩展与动画

翻译完成后，先停止加载动画，再显示译文并扩展窗口尺寸：

```swift
stopLoadingAnimation()
translationTextField.stringValue = trimmedTranslation
let contentSize = layoutContent(showTranslation: true, showLoading: false)
NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.18
    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    setWindowFrame(contentSize: contentSize, near: location, animated: true)
}
```

`layoutContent(showTranslation:showLoading:)` 根据不同状态计算布局与尺寸：

- **加载态**：隐藏译文标题和内容，仅显示原文与加载提示。
- **完成态**：显示译文标题和内容，隐藏加载提示。

### 5) 布局与内容尺寸

为了在不同状态下稳定排版，布局函数将显示内容作为显式参数：

```swift
private func layoutContent(showTranslation: Bool, showLoading: Bool) -> CGSize
```

通过条件累计高度与宽度，保证：

- 加载态窗口高度更小，避免空白区域。
- 完成态窗口扩展并对齐分隔线与译文内容。

## 交互细节

- 浮窗在 Force Click 时立即出现并可拖动。
- 翻译完成后窗口只做尺寸动画，不改变锚点逻辑。
- 关闭浮窗时会停止加载计时器，避免后台资源消耗。

## 相关代码位置

- `Sources/digger/digger.swift`：`ForceClickSelectionHandler`、`ForceClickSelectionPopup`
