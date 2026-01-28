# OpenAI 翻译弹窗接入说明

本文档记录本次 session 的实现内容、整体流程、关键模块职责与设计选择，便于后续维护与扩展。

## 目标概述

- force click 时读取选中文本
- 通过 OpenAI SDK 翻译文本（目标语言：简体中文）
- 弹窗同时显示原文与译文
- 原文/译文之间有分割线，并明确标注
- 原文仍输出到终端，同时新增译文输出

## 依赖与配置

### 依赖

使用 Swift Package Manager 引入 MacPaw/OpenAI：

- 依赖声明：`Package.swift`
- 目标依赖：`OpenAI`

### 环境变量

- `OPENAI_API_KEY`：必填，OpenAI API Key
- `OPENAI_ENDPOINT`：可选，OpenAI 兼容 API 的自定义端点
  - 示例：`https://api.openai.com/v1`

当未提供 `OPENAI_API_KEY` 时，弹窗内显示“未检测到 OPENAI_API_KEY”。

## 运行流程（高层）

1. `ForceClickMonitor` 触发 force click
2. `ForceClickSelectionHandler` 获取选中文本
3. 使用 `OpenAITranslator` 进行翻译
4. 在弹窗中展示原文与译文
5. 译文同时输出到终端

## 核心实现细节

### 1) OpenAI SDK 接入

`OpenAITranslator` 负责翻译逻辑，并从环境变量读取配置。

- 使用 `OpenAI.Configuration` 初始化客户端
- 根据 `OPENAI_ENDPOINT` 解析 host / basePath / scheme / port
- 选择 Chat Completions API（`ChatQuery`）

译文请求示例（伪代码）：

```swift
let query = ChatQuery(
  messages: [
    .system(.init(content: .textContent("Translate ... into Simplified Chinese"))),
    .user(.init(content: .string(text)))
  ],
  model: .gpt4_1_mini,
  temperature: 0.2
)
```

### 2) 并发与数据安全

`OpenAITranslator` 定义为 `actor`，确保并发访问安全：

- 通过 `await translator.translate(...)` 进行异步翻译
- 避免在 `Task` 中捕获非 Sendable 的对象

弹窗展示在 `MainActor` 中执行：

```swift
await MainActor.run {
  forceClickSelectionPopup.show(...)
}
```

### 3) 弹窗内容结构

弹窗由五个组件组成：

- 原文标题（“原文”）
- 原文内容
- 分割线
- 译文标题（“译文”）
- 译文内容

并通过 `ForceClickSelectionPopup.layoutContent()` 进行尺寸计算与布局。

### 4) 末尾吞字修复

针对“最后一行被裁切”的问题，采用以下组合方案：

- 文本测量使用 `NSAttributedString.boundingRect`
- 为高度计算增加缓冲（`+4`）
- 设置 `preferredMaxLayoutWidth`
- 强制 `wraps = true` / `usesSingleLineMode = false`
- 整体内容高度增加底部余量

这些调整一起避免了偶发的行高不足问题。

### 5) 终端输出

翻译完成后输出译文：

```swift
print("译文: \(translation)")
```

### 6) 流式译文与自动滚动

本次更新支持“流式输出”开关：

- 开启时：翻译结果按增量片段输出，弹窗内容实时追加
- 关闭时：仍使用一次性返回，逻辑保持原样

实现要点：

- `OpenAITranslator.translateStream(_:)` 使用 `chatsStream` 获取增量 `delta.content`
- `ForceClickSelectionHandler` 累积片段并在每次片段到达时刷新弹窗
- 弹窗更新始终滚动到底部，确保新增内容可见

偏好设置：

- “流式译文”开关保存在 `AppPreferences.translationStreamingEnabled()`

涉及文件：

- `Sources/digger/Translation/OpenAITranslator.swift`
- `Sources/digger/Selection/ForceClickSelectionHandler.swift`
- `Sources/digger/UI/ForceClickSelectionPopup.swift`
- `Sources/digger/Preferences/PreferencesWindowController.swift`

## 关键文件与职责

- `Package.swift`
  - 引入 OpenAI 依赖

- `Sources/digger/digger.swift`
  - `OpenAITranslator`：OpenAI SDK 封装与翻译逻辑
  - `ForceClickSelectionHandler`：触发翻译与弹窗展示
  - `ForceClickSelectionPopup`：UI 结构与布局

## 设计选择说明

- 使用 `ChatQuery` 而非 `Responses`：SDK 内 Chat API 稳定且满足需求
- `OpenAITranslator` 作为 `actor`：解决数据竞争问题
- 弹窗使用自定义布局：便于精细控制行高与分隔线

## 后续可扩展方向

- 支持语言自动识别与目标语言配置
- 增加“复制译文”按钮
- 对长文本添加滚动或最大高度
