# Session 实现说明：Popup Retry（强制 API）与位置保持

本文档记录本次 session 中为 popup 新增的 `retry` 按钮，以及与缓存和窗口定位相关的实现细节。

## 1. 目标与约束

本次实现目标：

- 在 popup 右上角按钮组最左侧新增 `retry` 按钮。
- 点击 `retry` 后，重跑当前查询。
- 重试时强制走 API，不允许被已有 cache 命中直接返回。
- 重试结果仍然要写入 cache，供后续普通查询复用。
- 重试后 popup 保持在原位置，不跟随当前鼠标位置跳动。

非目标：

- 不引入新的持久化结构。
- 不改变已有 cache key 规则与过期/回收策略。

## 2. 方案总览

整体改造分三层：

1. UI 层（popup）新增 `retry` 按钮与回调。
2. 调度层（runner）新增 `forceAPI` / `anchorLocation` 参数，控制“是否读 cache”和“popup 锚点来源”。
3. 翻译层（translator）新增 `useCache` 开关，实现“跳过读 cache，但保留写 cache”。

## 3. 关键实现

## 3.1 Popup 按钮与回调

在 `ForceClickSelectionPopup` 中新增：

- `retryButton`
- `onRetry: ((String, CGPoint) -> Void)?`

并将 header 右上角按钮顺序改为：

- `retry`
- `copyAll`
- `preferences`

点击 `retry` 时：

- 使用当前窗口 `frame` 反算 popup 锚点（`CGPoint`）。
- 将 `originalText` 与该锚点一起通过 `onRetry` 回传。

这样重试链路可以复用当前窗口位置，而不是读取当前鼠标位置。

## 3.2 重试入口绑定

在 `ForceClickSelectionHandler` 初始化时绑定 `forceClickSelectionPopup.onRetry`：

- 收到 `(text, anchorLocation)` 后调用：
  - `popupRunner.run(text: text, forceAPI: true, anchorLocation: anchorLocation)`

其中：

- `forceAPI: true` 表示禁用读 cache。
- `anchorLocation` 保证 popup 位置稳定。

## 3.3 Runner 层控制面

`PopupFunctionRunner.run(...)` 新增参数：

- `forceAPI: Bool = false`
- `anchorLocation: CGPoint? = nil`

行为：

- `anchorLocation != nil` 时优先用它作为 popup 锚点。
- 否则回退到旧行为（读取当前鼠标位置）。
- 在 streaming / non-streaming 两条路径都将 `forceAPI` 透传为 `useCache: !forceAPI`。

## 3.4 Translator 层缓存开关

`OpenAITranslator` 新增可选参数：

- `runPromptWithCacheInfo(..., useCache: Bool = true)`
- `runPromptStreamWithCacheInfo(..., useCache: Bool = true)`

关键语义：

- `useCache == true`：保持原行为（先查 cache，命中即返回）。
- `useCache == false`：跳过 `cachedOutput(...)`，直接请求 API。
- 两种模式下，只要请求 API 成功，结果都会 `storeOutput(...)` 写回 cache。

这保证了“强制 API”与“结果继续缓存”同时成立。

## 4. 位置保持的原理

popup 的常规定位逻辑为（简化）：

```text
origin.x = anchor.x + 12
origin.y = anchor.y - popupHeight - 12
```

因此可从当前 `window.frame` 反推锚点：

```text
anchor.x = window.minX - 12
anchor.y = window.maxY + 12
```

重试时使用该反推锚点，即可在内容刷新与窗口尺寸变化场景下，保持 popup 的视觉锚定位置一致。

## 5. i18n 文案

新增键：

- `popupRetry`

已补充：

- English: `Retry Query`
- 简体中文: `重试查询`
- 日本語: `再試行`

## 6. 主要变更文件

- `Sources/digger/UI/ForceClickSelectionPopup.swift`
- `Sources/digger/Selection/ForceClickSelectionHandler.swift`
- `Sources/digger/Selection/PopupFunctionRunner.swift`
- `Sources/digger/Translation/OpenAITranslator.swift`
- `Sources/digger/UIStrings.swift`

## 7. 验证建议

建议验证路径：

1. 使用同一段文本触发查询，确认命中 cache（旧行为）。
2. 点击 popup 右上角 `retry`，观察：
   - 本次应走 API（而非直接命中 cache）。
   - 结果正常返回并显示。
3. 再次以普通方式触发同一查询，应能命中最新缓存。
4. 将 popup 拖动到非默认位置后点击 `retry`，确认窗口位置保持不变，不跳到鼠标附近。

