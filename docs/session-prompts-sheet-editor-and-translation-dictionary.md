# Session Notes: Prompt Dictionary Translation and Sheet Editor

本文记录本次 session 中围绕 prompt 与编辑体验的改动，包含默认翻译 prompt 优化、Preferences 中 prompt 编辑交互重构，以及相关文案统一。

## 目标

- 翻译行为区分“句子翻译”和“单词词典化输出”。
- 保证句子翻译严格保留空行与格式，不输出冗余说明。
- 改善 Preferences 中长 prompt 的编辑体验，且不破坏表格布局。
- 统一 UI 语义，将用户可见的 `Function` 文案收敛为 `Prompt`。

## 代码改动概览

- `Sources/digger/Translation/PromptTemplates.swift`
  - 更新 `defaultTranslationPrompt`，支持单词词典模式与句子直译模式双分支。
- `Sources/digger/Preferences/PreferencesView.swift`
  - 将 prompt 编辑从 `popover` 方案重构为 `sheet` 方案。
  - 列表内保持单行预览，点击后进入独立多行编辑窗口。
  - 修复点击空白区域无法打开编辑的问题。
  - 调整新增行为：`+` 新增后不自动打开编辑窗口。
  - 修复多行编辑器 placeholder 与输入首行的对齐问题。
- `Sources/digger/UIStrings.swift`
  - 三种语言中将 `New Function` 等用户可见文案统一到 `Prompt` 语义。
- `docs/custom-functions-preferences.md`
  - 同步描述文本中的 `new function` -> `new prompt`。
- `docs/session-preferences-functions-controls.md`
  - 同步描述文本中的 `new custom function` -> `new custom prompt`。

## 默认翻译 Prompt（实现原理）

`defaultTranslationPrompt` 采用“先判别输入类型，再走对应输出协议”的策略：

- 单词模式：
  - 自动检测源语言（中/英）。
  - 输出词典条目风格：词条、可选音标、按词性分组的多个释义、例句与对应译句。
  - 明确禁止输出 `Language` 等冗余元信息。
- 非单词模式：
  - 直接在简体中文与英文之间互译。
  - 保留语义、语气、空行、缩进、换行、Markdown 结构、占位符、数字与专有名词。
  - 仅返回译文，不追加解释。

这样可以在不改调用链的前提下，通过 prompt 约束直接提升输出稳定性。

## Prompt 编辑交互重构（Popover -> Sheet）

### 为什么改为 Sheet

之前的 `popover + FocusState` 方案在多场景下容易出现焦点竞争与状态同步复杂度上升。改为 `sheet` 后：

- 不影响当前 table 布局高度与行密度。
- 焦点管理边界清晰，编辑状态由独立窗口承载。
- 组件更简单，状态更少，维护成本更低。

### 核心实现

- 新增 `PromptEditorTarget`：
  - `systemPrompt`
  - `customPrompt(UUID)`
- 通过 `.sheet(item: $promptEditorTarget)` 统一承载编辑窗口。
- 列表中的 prompt 区域使用“单行预览按钮”：
  - 文本显示首个非空行。
  - 空文本时显示 placeholder。
  - 点击输入框任意区域（含空白区域）都可打开编辑。
- 编辑窗口使用 `PromptEditorSheet` + `MultilinePromptEditor`：
  - 直接绑定原始数据（`$viewModel.systemPrompt` 或 `binding(for:keyPath:)`）。
  - `Done` 使用 `dismiss()` 关闭窗口。
  - `TextEditor` 在 `onAppear` 自动聚焦。
- 点击窗口外（应用失活）时，通过 `NSApplication.didResignActiveNotification` 关闭编辑窗口。

## 文案统一（Function -> Prompt）

`UIStrings` 中相关 key 的值已统一为 Prompt 语义，包含英文、简体中文、日文：

- `Untitled Function` -> `Untitled Prompt`
- `Add Function` -> `Add Prompt`
- `Function title` -> `Prompt title`
- `New Function` -> `New Prompt`
- 对应中文、日文等价表达也已同步。

## 最终交互行为

- 点击 `System Prompt` 或任意自定义 prompt 的单行区域，打开独立多行编辑窗口。
- 点击输入框空白区域同样可打开编辑窗口。
- 编辑窗口关闭后，列表布局不变化。
- 点击 `+` 仅新增并选中，不自动弹出编辑窗口。
- placeholder 与输入首行对齐，空文本进入编辑时可直接输入。

## 验证

建议执行：

```bash
swift build
```

预期：构建通过，且 Preferences > Prompts 的编辑交互符合上述行为。
