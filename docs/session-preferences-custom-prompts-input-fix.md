# Session Notes: Custom Prompts Input Fix

本文记录本次 session 中对 Preferences > Functions 自定义 prompts 编辑区的修复，重点是输入框颜色异常与新增/删除引发崩溃的问题。

## 背景与问题

- 自定义 prompts 的输入区域出现文本颜色异常，怀疑来源于 table 与输入框嵌套 wrapper。
- 点击 `+` 添加后再点击 `-` 删除会触发崩溃，报错为 `Index out of range`。

## 修复思路

- 移除 `List` / table 风格容器，改用更轻量的滚动容器，避免多层 wrapper 影响输入框颜色。
- 放弃基于数组 index 的绑定，改为基于 `id` 的字段级绑定，在列表变化时动态解析最新 index，避免删除时访问越界。

## 关键改动

### 1) 移除 table 风格 wrapper

- `List` 改为 `ScrollView + LazyVStack`。
- 行内容保持为 `HStack`，输入框样式复用 `preferenceInputStyle()`。
- 这样既避免了 table wrapper，也保留了滚动能力。

### 2) 绑定改为 id + keyPath

- 旧逻辑使用 `customFunctions.indices` 或 `Binding<CustomFunction>`，删除时容易出现旧 index。
- 新逻辑通过函数 `binding(for:id:keyPath:)` 在 `get/set` 时动态查找 index。
- 如果记录已不存在，`get` 返回空字符串，`set` 直接退出。

## 涉及文件

- `Sources/digger/Preferences/PreferencesView.swift`
  - Functions tab 列表布局改为 `ScrollView + LazyVStack`
  - `ForEach` 使用 `id` 驱动
  - 新增 `binding(for:keyPath:)` 字段级绑定

## 结果

- 自定义 prompts 的输入区域颜色恢复正常。
- `+` 添加后 `-` 删除不再触发 `Index out of range` 崩溃。
