# 多语言与翻译目标语言

本文档说明本次 session 中新增的多语言能力（中文/英语/日语）、Preferences 语言切换与翻译目标语言选择的实现原理。

## 功能概览

- 支持三种语言：English / 简体中文 / 日本語。
- Preferences 中新增 Language 下拉框，切换后即时生效。
- Preferences 中新增 Target Language 下拉框，用于选择翻译目标语言。
- UI 文案集中管理，后续扩展更多语言无需改动业务逻辑。

## 实现原理

### 1) 语言模型与持久化

新增 `AppLanguage` 枚举并持久化到 `UserDefaults`：

- Key: `AppLanguage`
- 默认值：English
- 切换语言后写入偏好设置，刷新 UI。

翻译目标语言使用独立的偏好项：

- Key: `TranslationTargetLanguage`
- 默认值：简体中文

### 2) 文案集中管理

新增 `UIStrings` 统一管理所有 UI 文案：

- 以 `Key` 作为稳定标识。
- 每种语言维护一份 key → string 的字典。
- 通过 `UIStrings.value(_:)` 读取当前语言的文案，若缺失则回退到英文。

### 3) 偏好页语言切换

Preferences 中新增 Language 下拉框：

- 使用 `NSPopUpButton` 展示 `AppLanguage.displayName`。
- 选择后保存语言，并触发 `onLanguageChange` 回调。
- 回调会刷新 Preferences、弹窗与菜单文字。

### 4) 翻译目标语言

Preferences 中新增 Target Language 下拉框：

- 使用 `TranslationTargetLanguage` 枚举管理目标语言。
- 选择后写入偏好设置，翻译时读取该设置作为目标语言。

翻译请求通过 system prompt 动态注入目标语言：

- `TranslationTargetLanguage.promptName` 用于生成 prompt 里的语言名称。
- 这样可以在不改业务逻辑的情况下扩展更多目标语言。

### 5) 运行时刷新

语言切换后即时更新：

- **弹窗**：调用 `ForceClickSelectionPopup.applyStrings()` 并重算布局。
- **菜单栏**：更新菜单标题与提示文本。
- **主菜单**：更新 Edit 菜单与系统项标题。
- **Preferences**：刷新标题、描述、标签文本。

## 关键文件

- `Sources/digger/UIStrings.swift`
  - `AppLanguage`、`TranslationTargetLanguage` 与文案字典
  - UI 字符串访问入口
- `Sources/digger/digger.swift`
  - 语言偏好持久化
  - Preferences 语言/目标语言选择控件
  - 菜单与弹窗即时刷新

## 扩展建议

- 新增语言：补齐 `UIStrings.strings` 中对应语言字典即可。
- 若文案数量增长，可考虑将字典拆分到独立文件或生成化管理。
