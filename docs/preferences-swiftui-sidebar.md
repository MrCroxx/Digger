# Preferences SwiftUI Sidebar 改造

本文记录本次 session 中对 Preferences 的 SwiftUI 原生侧边栏实现，以及关键实现原理。

## 目标

- 使用 SwiftUI 的官方方式实现 macOS 原生侧边栏样式。
- 保持原有 Preferences 行为不变（自动保存、设置项回调、快捷键录入、自定义功能列表等）。

## 关键组件

- `NavigationSplitView`：负责左右分栏结构。
- `List` + `.listStyle(.sidebar)`：声明左侧为 Sidebar 风格列表。

## 文件变更

- 新增 SwiftUI 视图：`Sources/digger/Preferences/PreferencesView.swift`
- 新增 ViewModel：`Sources/digger/Preferences/PreferencesViewModel.swift`
- 用 SwiftUI 替换 AppKit Preferences 窗口：`Sources/digger/Preferences/PreferencesWindowController.swift`

## 实现原理

### 1) 侧边栏结构

`PreferencesView` 使用 `NavigationSplitView` 作为根布局：

- 左侧：`List` 加 `.listStyle(.sidebar)`，列出各 tab（General/Popup/Functions/Advanced/API）。
- 右侧：根据 `selection` 切换具体设置页面内容。

这组合会触发系统默认的 Sidebar 样式（与 Finder 类似）。

### 2) ViewModel 负责数据同步

`PreferencesViewModel` 是 `ObservableObject`，将 `AppPreferences` 中的设置映射成 `@Published` 字段。

- 打开窗口时 `refresh()`，保证 UI 与当前偏好一致。
- 设置项更新时，通过 `onChange` 把变更写回 `AppPreferences`。

这样既保持自动保存，也能复用既有偏好存储逻辑。

### 3) 各页面布局与行为

- 使用 `Form + LabeledContent` 实现系统风格设置项布局。
- 数值输入依旧做格式化与边界校验（字体大小、延迟、窗口大小、Force Click 参数等）。
- 语言切换后，回调外层进行 popup 和菜单文案刷新。

### 4) 快捷键录入保持原行为

原来的 `ShortcutRecorderField` 是 AppKit 控件，SwiftUI 通过 `NSViewRepresentable` 包装为 `ShortcutRecorderView`：

- 复用原来的快捷键捕获逻辑。
- 通过 binding 同步当前快捷键。

### 5) 自定义功能列表

自定义功能列表使用 SwiftUI `List` 展示：

- 行内 `TextField` 编辑 title 和 prompt。
- `Add`/`Remove` 操作同步 `AppPreferences`。
- 使用 selection 保持当前选中行。

## 入口与窗口承载

`PreferencesWindowController` 仍作为入口，但内容改为 `NSHostingController`：

- 通过 `PreferencesView` 渲染 SwiftUI 界面。
- 保留原窗口风格参数（尺寸、标题、透明标题栏、拖动行为等）。

## 行为对齐点

- 所有设置项仍然自动保存。
- Force Click 参数变更会即时回调到监控逻辑。
- Popup 字号与布局变更会触发回调更新。
- 自定义功能列表保持原先的数据结构和存储方式。

## 可能的后续优化

- 为 Functions 列表增加更强的编辑体验（多行 prompt 或自适应高度）。
- 对数值输入添加更明确的格式提示或单位说明。
