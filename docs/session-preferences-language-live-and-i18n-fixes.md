# Session Notes: Preferences Language Live Apply and i18n Text Fixes

本文档记录本次 session 在 Preferences 中完成的两类修复：

- 修复 Language 切换后需失焦才生效的问题，改为切换后立即生效。
- 修复与“流式输出”相关的多语言文案语义不准确和局部未本地化问题。

## 背景与问题

### 1) Language 切换延迟生效

现象：在 Preferences 的 Language 下拉框切换语言后，界面文案不会立即刷新，通常要等到焦点变化后才体现。

目标：语言切换动作发生时，立即写入偏好并触发整体验证链路（Preferences / 菜单 / 弹窗）刷新。

### 2) 多语言文案不一致

现象：

- 中文文案为“流式译文”，语义偏向翻译结果，不够准确。
- 同一页面存在局部中英混排（如 `Prompt`、`输入 prompt`）。

目标：统一表达为“流式输出”，并修复明显未本地化文本。

## 实现原理

## 1) 语言切换即时生效

文件：`Sources/digger/Preferences/PreferencesView.swift`

核心调整：

- 将 Language `Picker` 的绑定从直接 `$viewModel.language` 改为自定义 `languageBinding`。
- 在 `languageBinding.set` 中，以单次状态更新流程完成：
  - `AppPreferences.setLanguage(newValue)`
  - `viewModel.language = newValue`
  - `onLanguageChange()`
- 移除原有 `.onChange(of: viewModel.language)` 里的语言写入与回调逻辑。

这样做的关键点：

- `Picker` 选择变化时，先落盘语言，再更新视图状态并立刻触发跨模块字符串刷新。
- 避免了“依赖后续焦点变化或其他事件驱动重绘”的延迟感知问题。

## 2) i18n 文案语义与一致性修复

文件：`Sources/digger/UIStrings.swift`

本次修复项：

- `preferencesStreamingLabel`
  - English: `Stream Translation` -> `Stream Output`
  - 简体中文: `流式译文` -> `流式输出`
  - 日本語: `ストリーミング翻訳` -> `ストリーミング出力`
- 中文未本地化修复：
  - `preferencesFunctionPromptLabel`: `Prompt` -> `提示语`
  - `preferencesFunctionPromptPlaceholder`: `输入 prompt` -> `输入提示语`

## 影响范围

- Preferences > General：Language 切换即时生效。
- Preferences 文案：流式开关标签语义统一为“流式输出”。
- Preferences > Prompts：中文场景下不再出现明显中英混排。

## 一致性检查结论

在 Preferences 内，其他“切换型配置项”（如 `Stream Output`、`Start on Login`、滑杆类配置）仍保持值变化即应用。

说明：部分数值输入框（如若干 `TextField`）仍采用“失焦提交”策略，这是当前输入体验设计，不属于本次 bug 范畴。

## 建议验证步骤

1. 打开 Preferences，保持窗口焦点不变，直接切换 Language，确认标题、侧栏 tab、内容标签立即更新。
2. 切换到中文，确认 General 中对应开关显示“流式输出”。
3. 切换到日文，确认对应开关显示“ストリーミング出力”。
4. 切换到中文的 Prompts 页，确认“提示语”列名和“输入提示语”占位文案正确显示。
5. 切回英文，确认 `Stream Output` 与 `Prompt` 系列表达一致。

## 后续建议

- 若未来继续扩展语言，建议在 `UIStrings.Key` 增减时引入简单的完整性检查脚本，减少漏翻和混排回归。
