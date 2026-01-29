# Preferences Sidebar 视觉与布局调整

本文记录本次 session 中对 Preferences 页面布局与视觉的关键改动，目标是移除可折叠的 sidebar 行为，保持功能不变，并统一风格与对齐。

## 目标

- 不使用 `NavigationSplitView`，避免系统 sidebar 的 collapse toggle。
- 左右分栏用竖线分隔，整体保持系统灰色背景。
- 右侧内容标题固定在顶部，并用横线与内容分隔。
- 所有输入框统一样式，确保标题与控件对齐且不换行。
- 将“Settings are saved automatically”提示作为全局提示放在左侧底部。

## 关键实现

### 1) 自定义左右分栏

使用 `HStack` 作为容器：

- 左侧：`List`（sidebar 样式）
- 中间：`Divider()`
- 右侧：`detailView`

这样不会触发系统的 sidebar toggle，同时保留原有 tab 切换逻辑。

### 2) 统一灰色背景

- 左侧与右侧统一使用 `Color(nsColor: .windowBackgroundColor)`。
- `List` 使用 `scrollContentBackground(.hidden)` + 统一背景，避免提示区域颜色不一致。

### 3) 右侧标题与内容分隔

- 标题紧贴顶部（无顶部 padding）。
- 标题下方 `Divider()`，并增加轻微上下间距。
- 内容整体放在标题下方，`padding(.top, 16)`。

### 4) 输入框统一样式

新增 `preferenceInputStyle()` 统一输入框外观：

- 白色底
- 轻微圆角
- 细分隔线描边

并应用到所有 `TextField`/`SecureField`/`ShortcutRecorderView`。

### 5) 标题与输入框对齐

`LabeledContent` 的 label 使用固定宽度 `preferenceLabel()`，确保：

- 标题不换行
- 标题列统一对齐

### 6) 全局提示位置

“Settings are saved automatically” 移至左侧栏底部，作为全局提示：

- 视觉更明确地表达该提示作用于全局
- 与左侧背景统一，避免突兀

## 文件变更

- `Sources/digger/Preferences/PreferencesView.swift`
  - 替换 `NavigationSplitView` 为 `HStack + Divider`
  - 右侧标题/分割线/内容布局调整
  - 统一输入框样式与 label 对齐策略
  - 全局提示移动到左侧底部
- `Sources/digger/Preferences/PreferencesWindowController.swift`
  - 调整窗口初始宽度以保证标题单行显示

## 行为对齐点

- 所有设置仍自动保存
- popup/force click/自定义函数等回调逻辑保持不变
- tab 切换与选中逻辑不变
