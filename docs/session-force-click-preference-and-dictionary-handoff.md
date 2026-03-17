# Force Click Preference and Dictionary Handoff

本文档记录本次 session 中围绕 Force Click 偏好设置完成的两项改动：

1. 新增一个 preference，用于关闭 Force Click 触发 `digger` popup。
2. 修复关闭该 preference 后仍会干扰系统字典弹窗的问题。

## 背景

此前 Preferences 中存在一个 `Advanced` tab，内容实际上都是 Force Click 判定参数：

- `FORCE_CLICK_PRESSURE_THRESHOLD`
- `FORCE_CLICK_PRESSURE_DELTA`
- `FORCE_CLICK_BASELINE_WINDOW_MS`

同时，Force Click 一旦被 `digger` 检测到，就会走自定义 popup 流程，并通过 `CGEventTap` suppress 后续鼠标事件，以阻止系统 Look Up/字典弹窗。

这带来两个问题：

- 配置入口命名不准确：`Advanced` 实际上承载的是 Force Click 相关配置。
- 缺少总开关：用户无法只保留系统 Force Click 字典，而关闭 `digger` popup。

## 改动一：新增 Force Click Popup 开关

### 目标

- 提供一个显式开关，让用户可以关闭 Force Click 触发 popup。
- 将该开关与 Force Click 灵敏度参数放在同一处配置。
- 将 tab 名称从 `Advanced` 改为 `Force Click`。

### 实现

在 `AppPreferences` 中新增布尔持久化项：

- key: `ForceClickPopupEnabled`
- default: `true`

`PreferencesViewModel` 新增 `forceClickPopupEnabled` 字段，Preferences UI 在原 `Advanced` pane 顶部新增 Toggle：

- English: `Show Popup on Force Click`
- 简体中文: `Force Click 时显示弹窗`
- 日本語: `Force Click でポップアップを表示`

同时将 tab 标题文案统一改为 `Force Click`。

### 影响

- 开启时：Force Click 继续触发 `digger` popup。
- 关闭时：Force Click 不再显示 `digger` popup。
- 快捷键触发 popup 的能力不受影响。

## 改动二：修复系统字典闪现后折叠

### 现象

当用户关闭 “Show Popup on Force Click” 后，系统字典不再被完全取代，但仍会短暂显示后立刻折叠。

### 根因

第一次实现只关闭了 popup 展示逻辑，没有关闭 Force Click 的事件接管链路：

1. `ForceClickSelectionHandler.handleForceClick()` 根据 preference 跳过 `popupRunner.run(...)`。
2. 但 `ForceClickMonitor` 仍会在检测到 force click 后把自己标记为 `active`。
3. `EventTapController` 在 `monitor.shouldSuppressEvents()` 为 `true` 时，继续吞掉 `leftMouseUp` / `leftMouseDragged` 等鼠标事件。
4. 系统字典先被系统显示出来，但随后因事件被中途 suppress 而立刻折叠。

也就是说，之前关闭的是“显示 popup”，不是“禁用 `digger` 对这次 force click 的接管”。

### 修复方案

将该 preference 的语义提升为“是否允许 `digger` 接管 force click”。

具体做法：

1. 在 `ForceClickMonitor.update(touches:)` 中，若 `ForceClickPopupEnabled == false`：
   - 立即将 `active` 置为 `false`
   - 清除本次按压周期内的 `hasForceClicked`
   - 不触发 `onForceClick()`
2. 在 `ForceClickMonitor.shouldSuppressEvents()` 中再次读取该 preference：
   - 若已关闭，则直接返回 `false`

### 修复后的行为

- 开关开启：
  - `digger` 检测并接管 force click
  - 显示 popup
  - suppress 系统字典相关鼠标事件
- 开关关闭：
  - `digger` 不接管这次 force click
  - 不显示 popup
  - 不 suppress 鼠标事件
  - 系统字典按原生逻辑正常显示和保持

## 涉及文件

- `Sources/digger/Preferences/AppPreferences.swift`
- `Sources/digger/Preferences/PreferencesViewModel.swift`
- `Sources/digger/Preferences/PreferencesView.swift`
- `Sources/digger/UIStrings.swift`
- `Sources/digger/Selection/ForceClickSelectionHandler.swift`
- `Sources/digger/Core/ForceClickMonitor.swift`
- `Sources/digger/App/Digger.swift`
- `Sources/digger/EventTap/EventTap.swift`

## 验证点

1. 打开 Preferences，确认左侧 tab 名称已从 `Advanced` 改为 `Force Click`。
2. 在 `Force Click` tab 中确认新增 toggle 与三项灵敏度参数显示在同一页。
3. 开启 toggle 后执行 force click：
   - `digger` popup 正常出现
   - 系统字典不出现
4. 关闭 toggle 后执行 force click：
   - `digger` popup 不出现
   - 系统字典正常出现且不会闪退
5. 使用快捷键触发 popup：
   - 仍应正常工作，不受该 toggle 影响
