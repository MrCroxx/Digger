# Session 实现说明：Popup 复制快捷键与居中成功提示

本文档记录本次 session 中为 popup 新增的复制能力与交互反馈优化，包括：

- 当焦点位于 popup 时支持 `cmd+c` / `cmd+shift+c`
- 两种复制语义不同（不含原文 / 含原文）
- 复制成功提示按功能区分文案
- 复制成功提示改为在 popup 中央显示

## 1. 目标与行为定义

### 1.1 快捷键行为

当 popup 为当前焦点窗口时：

- `cmd+c`：复制所有结果分区，不包含原文
- `cmd+shift+c`：复制原文 + 所有结果分区

### 1.2 复制成功反馈

- 复制成功后显示短暂提示
- 提示内容与复制语义一致：
  - 不含原文复制成功
  - 含原文复制成功
- 提示位置为 popup 窗口中央（而非按钮右上角附近）

## 2. 方案总览

实现拆分为三层：

1. **窗口快捷键拦截层**：在 `PopupWindow` 统一识别 `cmd+c` / `cmd+shift+c`
2. **复制语义层**：在 `ForceClickSelectionPopup` 统一拼接文本并按语义复制
3. **反馈展示层**：在 `HoverTooltipWindow` 增加居中展示能力，复制成功统一走居中提示

## 3. 实现原理

### 3.1 在窗口层统一拦截复制快捷键

在 `PopupWindow` 中重写 `performKeyEquivalent(with:)`，判断是否为复制组合键：

- 只接受主键 `c`
- 修饰键为 `.command` 时，映射为 `includeOriginal = false`
- 修饰键为 `[.command, .shift]` 时，映射为 `includeOriginal = true`

然后通过回调 `onCopyShortcut: ((Bool) -> Bool)?` 将语义传递给 popup 逻辑层。这样可以保证无论焦点位于 popup 的哪个子视图，复制行为都一致。

### 3.2 复制内容构建统一收敛

在 `ForceClickSelectionPopup` 中新增统一路径：

- `combinedResultText(includeOriginal:)`
- `copyCombinedResults(includeOriginal:)`
- `handleCopyShortcut(includeOriginal:)`

核心点：

- 通过 `includeOriginal` 决定是否拼入原文段落
- 功能分区只复制已完成且非空结果
- 复制按钮与快捷键复用同一拼接/写剪贴板路径，避免逻辑分叉

### 3.3 复制反馈改为 popup 中心定位

原有 tooltip 仅支持 `show(text:near:fontSize:)`（锚定按钮附近）。

本次在 `HoverTooltipWindow` 中新增：

- `showCentered(text:in:fontSize:)`

并把布局计算抽到共享函数，复用同一文本测量与尺寸计算逻辑。复制成功时改为：

- 取当前 `window.frame`
- 使用 `showCentered(...)` 显示提示
- 定时器超时后自动隐藏

因此复制反馈不再依赖按钮位置，而是稳定显示在 popup 中央。

### 3.4 文案按复制语义区分

新增 i18n key：

- `popupCopyAllWithoutOriginalSuccess`
- `popupCopyAllWithOriginalSuccess`

并在 English / 简体中文 / 日本語中补充对应文本。快捷键复制成功时根据 `includeOriginal` 选择不同提示。

## 4. 主要变更文件

- `Sources/digger/UI/ForceClickSelectionPopup.swift`
  - 复制快捷键回调接线
  - 复制内容拼接与复制路径收敛
  - 复制成功提示改为居中
- `Sources/digger/UIStrings.swift`
  - 新增两条复制成功文案 key 与多语言实现

## 5. 兼容性与边界说明

- 仅在 popup 作为当前键窗口时接管 `cmd+c` / `cmd+shift+c`
- 非复制组合键仍走系统默认事件分发
- 当可复制内容为空时，不会写入剪贴板，也不会显示成功提示

## 6. 验证建议

建议按以下路径验证：

1. 弹出 popup，等待至少一个分区有结果
2. 按 `cmd+c`，检查剪贴板不含原文，且中央提示为“无原文”语义
3. 按 `cmd+shift+c`，检查剪贴板包含原文，且中央提示为“含原文”语义
4. 点击任意复制按钮，确认成功提示也在 popup 中央
5. 在不同语言下切换，确认成功提示文案正确切换
