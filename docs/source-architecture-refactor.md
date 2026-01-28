# Source Architecture Refactor (Session Notes)

本次 session 的目标是将原来的单文件 `Sources/digger/digger.swift` 拆分为按功能模块组织的源码结构，降低耦合、提升可维护性，并便于后续扩展。

## 设计目标

- **按职责分层**：入口、事件、选区、翻译、偏好设置、UI 拆分到独立目录。
- **依赖方向清晰**：低层模块不反向依赖 UI，UI 只通过公开 API 交互。
- **行为不变**：所有拆分仅为组织结构调整，不改业务逻辑。

## 新的目录结构

```
Sources/digger/
  App/
    Digger.swift
  Core/
    ForceClickMonitor.swift
  EventTap/
    EventTap.swift
  Preferences/
    AppPreferences.swift
    PopupFontPreferences.swift
    PreferencesWindowController.swift
  Selection/
    AccessibilityHelpers.swift
    ForceClickSelectionHandler.swift
    SelectionModels.swift
  Translation/
    OpenAITranslator.swift
  UI/
    ForceClickSelectionPopup.swift
    MenuBarController.swift
  UIStrings.swift
```

## 模块职责

- `App/`：应用入口、主菜单注册、核心对象装配。
- `Core/`：核心逻辑（如 force click 判定），无 UI 依赖。
- `EventTap/`：输入事件拦截与分发。
- `Preferences/`：持久化配置与偏好设置窗口。
- `Selection/`：可访问性选区读取、缓存与剪贴板回退逻辑。
- `Translation/`：OpenAI 相关翻译请求。
- `UI/`：弹窗与菜单栏 UI。
- `UIStrings.swift`：多语言文本与语言枚举。

## 依赖方向与流程

整体流程保持不变，入口在 `Sources/digger/App/Digger.swift`：

1. `Digger.main()` 装配 `ForceClickMonitor`、`ForceClickSelectionHandler`、`ForceClickEventTap`。
2. `OMSManager` 异步流更新触控压力，交给 `ForceClickMonitor.update(...)` 判定。
3. 触发 force click 后由 `ForceClickSelectionHandler` 读取文本并调用 `OpenAITranslator`。
4. 翻译结果通过 `ForceClickSelectionPopup` 展示。
5. 偏好设置通过 `PreferencesWindowController` 修改 `AppPreferences` 并热更新相关参数。

模块之间的依赖方向简化为：

- `App` 依赖所有模块进行组装。
- `Core/EventTap/Selection/Translation/Preferences/UI` 之间只有必要的单向引用。

## 旧文件到新文件映射

为了兼容已有文档，下面是常见类型与新文件位置的对应关系：

- `Digger` / 主菜单：`Sources/digger/App/Digger.swift`
- `ForceClickMonitor`：`Sources/digger/Core/ForceClickMonitor.swift`
- `EventTapController` / `ForceClickEventTap`：`Sources/digger/EventTap/EventTap.swift`
- `ForceClickSelectionHandler`：`Sources/digger/Selection/ForceClickSelectionHandler.swift`
- `SelectionSnapshot` / `PasteboardSnapshot`：`Sources/digger/Selection/SelectionModels.swift`
- `findSelectedText` / `copyAttribute`：`Sources/digger/Selection/AccessibilityHelpers.swift`
- `OpenAITranslator`：`Sources/digger/Translation/OpenAITranslator.swift`
- `ForceClickSelectionPopup` / `PopupWindow`：`Sources/digger/UI/ForceClickSelectionPopup.swift`
- `MenuBarController`：`Sources/digger/UI/MenuBarController.swift`
- `AppPreferences` / `PopupFontPreferences`：`Sources/digger/Preferences/*.swift`

## 注意事项

- 现有文档若仍引用 `Sources/digger/digger.swift`，请按“旧文件到新文件映射”查找对应位置。
- 本次改动仅重排文件与可见性，逻辑行为保持一致。
