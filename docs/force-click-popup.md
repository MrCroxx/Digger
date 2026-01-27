# Force Click 选中文本浮窗

本文档说明 `digger` 在 Force Click 触发时，如何在鼠标附近显示选中文本浮窗，并在按下 Esc 或点击窗口外时关闭。

入口实现位于 `Sources/digger/digger.swift`。

## 目标与约束

- **就地提示**：浮窗位置接近鼠标，便于快速确认选中文本。
- **避免干扰**：弹窗不阻止其他交互，点击外部即可关闭。
- **统一输入捕获**：使用现有的 `CGEventTap` 处理 Esc/点击，避免 AppKit 监听失效。

## 总体流程

1. Force Click 触发后，获取选中文本。
2. 调用浮窗 `show(text:near:)`，在鼠标附近展示文本。
3. 由 `CGEventTap` 监听 Esc 与鼠标点击，满足条件时关闭浮窗。

## 关键实现

### 1) Force Click 触发后显示浮窗

`ForceClickSelectionHandler` 在获取文本后调用浮窗：

```swift
print(text)
showPopup(for: text)
```

`showPopup` 由主线程执行，避免跨线程访问 AppKit：

```swift
Task { @MainActor in
    forceClickSelectionPopup.show(text: text, near: location)
}
```

### 2) 浮窗本体

浮窗使用 `PopupWindow`（无边框、浮动层级），并允许成为 key window：

```swift
window = PopupWindow(
    contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
window.level = .floating
window.collectionBehavior = [.canJoinAllSpaces, .transient]
```

显示时将窗口移动到鼠标附近并置顶：

```swift
window.setFrameOrigin(origin)
NSApp.activate(ignoringOtherApps: true)
window.makeKeyAndOrderFront(nil)
```

### 3) Esc / 外部点击关闭

不依赖 AppKit 事件监听器，直接在 `CGEventTap` 中判断：

```swift
case .keyDown:
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    if keyCode == CGKeyCode(kVK_Escape) {
        Task { @MainActor in
            forceClickSelectionPopup.dismissOnEscape()
        }
    }
case .leftMouseDown, .rightMouseDown:
    let location = event.location
    Task { @MainActor in
        forceClickSelectionPopup.dismissIfClickOutside(location)
    }
```

浮窗内部仅提供两种关闭入口：

```swift
func dismissOnEscape() {
    window.orderOut(nil)
}

func dismissIfClickOutside(_ location: CGPoint) {
    if !window.frame.contains(location) {
        window.orderOut(nil)
    }
}
```

## 权限说明

- **Accessibility 权限**：Force Click 的鼠标事件拦截与注入依赖该权限。
- **Input Monitoring 权限**：捕获全局键盘事件（Esc）需要该权限。

## 相关代码位置

- `Sources/digger/digger.swift`：`ForceClickSelectionPopup`、`PopupWindow`、`EventTapController`
