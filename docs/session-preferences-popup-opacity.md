# Session Notes: Popup Opacity Preference

本文整理本次在 Preferences 中新增「弹窗透明度」配置（`0-100` 滑动）的实现方案与原理。

## 目标

- 在 `Preferences > Popup` 中新增透明度滑块，范围 `0...100`，步进 `1`。
- 配置持久化到 `UserDefaults`，重启后保持。
- 修改值后即时生效到当前弹窗背景。
- 保持现有布局与文字可读性，不影响其他功能（字号、布局、快捷键等）。

## 实现原理

整体采用与现有偏好一致的单向数据流：

1. `AppPreferences` 负责配置读写与边界钳制。
2. `PreferencesViewModel` 暴露 UI 绑定值。
3. `PreferencesView` 使用 `Slider` 展示/编辑值，并在变化时写回配置。
4. `PreferencesWindowController` 与 `Digger` 通过回调把配置变化传递到运行时对象。
5. `ForceClickSelectionPopup` 接收新值并更新背景 alpha。

这样做的核心是把「持久化」「UI 编辑」「运行时渲染」三层解耦，避免直接在视图层操作弹窗对象。

## 关键改动

### 1) 偏好存储层

文件：`Sources/digger/Preferences/AppPreferences.swift`

- 新增 key：`PopupOpacity`
- 新增默认值：`defaultPopupOpacity = 92`
- 新增 API：
  - `popupOpacity() -> CGFloat`
  - `setPopupOpacity(_ value: CGFloat)`

边界策略：统一钳制到 `0...100`，避免非法值污染配置。

### 2) ViewModel 层

文件：`Sources/digger/Preferences/PreferencesViewModel.swift`

- 新增 `@Published var popupOpacity: Double`
- 在 `refresh()` 中同步读取最新配置

目的：保证 Preferences 窗口重新打开或刷新后，UI 与持久化状态一致。

### 3) Preferences UI 层

文件：`Sources/digger/Preferences/PreferencesView.swift`

- 新增回调注入：`onPopupOpacityChange: (CGFloat) -> Void`
- 在 Popup 面板新增滑块：
  - `Slider(value: $viewModel.popupOpacity, in: 0...100, step: 1)`
  - 右侧显示百分比文本（如 `92%`）
- 新增 `onChange`：
  - 先做 `0...100` 钳制
  - 写入 `AppPreferences.setPopupOpacity(...)`
  - 触发 `onPopupOpacityChange(...)` 实时更新弹窗

### 4) 运行时接线

文件：

- `Sources/digger/Preferences/PreferencesWindowController.swift`
- `Sources/digger/App/Digger.swift`

改动：

- `PreferencesWindowController.init(...)` 增加 `onPopupOpacityChange` 参数并透传给 `PreferencesView`。
- `Digger` 在创建 Preferences controller 时注入：
  - `forceClickSelectionPopup.applyPopupOpacity(newOpacity)`

这样配置变化可以直接作用于正在运行的弹窗实例。

### 5) Popup 渲染层

文件：`Sources/digger/UI/ForceClickSelectionPopup.swift`

- 新增方法：`applyPopupOpacity(_ opacity: CGFloat)`
- 方法内部将 `0...100` 映射为 `0...1`，更新：
  - `contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(opacity / 100).cgColor`
- 初始化时读取并应用偏好值：
  - `applyPopupOpacity(AppPreferences.popupOpacity())`

注意：该实现只调整弹窗背景透明度，不改变文本/按钮 alpha，目的是保持内容可读性与交互稳定性。

## 本地化文案

文件：`Sources/digger/UIStrings.swift`

新增 key：`preferencesPopupOpacityLabel`

- English: `Popup Opacity`
- 简体中文：`弹窗透明度`
- 日本語：`ポップアップの透明度`

## 为什么这样设计

- 与现有偏好系统一致，维护成本低。
- 回调链路清晰，避免跨层直接耦合。
- 背景 alpha 调整比整窗 alpha 更稳，不会让前景文字也一起发灰。
- 通过存储层钳制范围，防止异常输入导致显示异常。

## 建议验证步骤

1. 打开 Preferences，进入 Popup 页，拖动透明度滑块到 `0`、`50`、`100`。
2. 触发弹窗，观察背景透明度是否与设定一致。
3. 修改透明度后不关闭弹窗，确认视觉变化可即时生效。
4. 重启应用，确认透明度配置仍然保留。
5. 在中文/英文/日文下检查标签文案是否正确显示。

## 影响范围

本次改动仅影响 Popup 偏好与弹窗背景渲染路径，不涉及：

- Force click 检测参数
- Prompt 执行与流式输出逻辑
- 缓存策略与 API 调用路径
