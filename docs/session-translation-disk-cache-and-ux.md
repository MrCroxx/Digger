# Session 实现说明：本地翻译缓存（Disk Cache）与命中可视化

本文记录本次 session 中围绕 OpenAI 请求链路新增的本地缓存能力，以及配套的 Preferences 与弹窗交互改造。

## 1. 目标与边界

本次实现目标：

- 将翻译/Prompt 请求结果缓存到本地文件系统。
- 当输入与上下文一致时直接命中缓存，跳过 API 调用。
- 缓存键使用哈希，不直接将输入/prompt/model 作为明文键保存。
- 在 Preferences 中可配置缓存容量上限（默认 `1 GiB`）。
- 在 Preferences 中可配置缓存 TTL（过期时间，默认 `168 hours`）。
- 回收策略同时考虑：
  - 超容量时按时间回收；
  - 即使未超容量，超过 TTL 也要过期并重新请求 API。
- 命中提示由“全局右上角”改为“每个命中的 section 独立显示”，位置在 section 右上角，位于复制/折叠按钮左侧。

不在本次范围：

- 跨设备同步缓存。
- 缓存加密。
- 缓存内容压缩。

## 2. 关键设计

### 2.1 缓存容器

新增 `TranslationDiskCache`（`actor`）作为唯一缓存读写入口，避免并发读写竞争。

职责：

- 生成请求键（基于哈希）。
- 从磁盘加载缓存并校验合法性。
- 写入缓存。
- 按 TTL 与容量执行回收。
- 提供缓存目录位置给 UI（用于 Finder 打开）。

### 2.2 请求键（Key）策略

缓存命中条件由以下要素共同决定：

- input
- prompt
- systemPrompt
- model
- endpoint
- schemaVersion

每个要素先做 SHA-256，再组合出最终 `keyHash`。

示意：

```text
inputHash = sha256(input)
promptHash = sha256(prompt)
systemPromptHash = sha256(systemPrompt)
modelHash = sha256(model)
endpointHash = sha256(endpoint)
keyHash = sha256("v{schemaVersion}|{inputHash}|{promptHash}|{systemPromptHash}|{modelHash}|{endpointHash}")
```

### 2.3 磁盘存储模型

缓存目录：

- `~/Library/Caches/digger/translation-cache`

每条缓存为单文件 JSON，文件名为 `<keyHash>.json`。

示意结构：

```json
{
  "version": 1,
  "inputHash": "...",
  "promptHash": "...",
  "systemPromptHash": "...",
  "modelHash": "...",
  "endpointHash": "...",
  "keyHash": "...",
  "output": "...",
  "createdAt": 1739270400000
}
```

说明：

- 键相关信息均为 hash，不用明文作为索引键。
- `output` 以明文存储（用于直接展示结果）。
- 命中后会更新文件 `modificationDate`，用于容量回收时的“最近访问”排序。

## 3. 请求链路改造

### 3.1 `OpenAITranslator`

新增结构：

- `PromptResult { output, isCacheHit }`
- `PromptStreamResult { stream, isCacheHit }`

读路径：

1. 计算 key。
2. 先查 `TranslationDiskCache.cachedOutput(...)`。
3. 命中则直接返回（不触发 API）。

写路径：

1. 未命中 -> 调用 API。
2. 获取结果后写入缓存。

### 3.2 Streaming 路径（关键行为）

为了避免 cache 命中时进入 streaming 状态机引发多次 UI 刷新：

- 当 `runPromptStreamWithCacheInfo(...)` 返回 `isCacheHit == true` 时，Runner 不再走 `markStreamingStarted -> incremental update`。
- 直接消费缓存流并一次性发布 final 结果。

## 4. 回收策略

回收按“先 TTL、后容量”的顺序执行。

### 4.1 TTL（过期时间）

- 新增配置：`translationCacheTTLHours`（默认 `168` 小时）。
- 读取缓存时，若 `now - createdAt > ttl`：
  - 当前缓存视为失效；
  - 删除文件；
  - 返回 miss，重新访问 API。

### 4.2 容量上限

- 新增配置：`translationCacheMaxSizeGiB`（默认 `1`）。
- `pruneIfNeeded()` 在执行容量裁剪前先清理过期项。
- 若仍超限，按 `modificationDate` 从旧到新删除，直到不超限。

说明：

- 容量回收语义近似 LRU（基于文件访问更新时间）。
- TTL 为硬约束，优先级高于容量。

### 4.3 特殊值语义

- `maxSizeGiB <= 0`：清空缓存并禁用缓存保留。
- `ttlHours <= 0`：缓存立即过期（等价于不保留可复用缓存）。

## 5. Preferences / UI 改造

### 5.1 独立 Cache Tab

在 Preferences 中新增独立 `Cache` tab，承载缓存相关设置：

- `Cache Max Size (GiB)`
- `Cache TTL (Hours)`
- `Open Cache Directory`（在 Finder 打开缓存目录）

配置提交后会触发一次 `pruneIfNeeded()`，确保新策略立即生效。

### 5.2 多语言文案

新增/更新文案键：

- `preferencesTabCache`
- `preferencesCacheMaxSizeLabel`
- `preferencesCacheTTLHoursLabel`
- `preferencesOpenCacheDirectoryButton`
- `popupCacheHit`

## 6. Popup 命中提示改造

### 6.1 由全局提示改为 section 提示

原方案：任一命中时在 popup 全局右上角显示图标。  
现方案：仅在命中的 section 右上角显示命中图标。

### 6.2 布局位置

section 右上角按钮顺序为：

- cache-hit icon
- copy
- collapse

图标位于 copy/collapse 左侧，符合可读性与局部反馈原则。

### 6.3 状态更新方式

`updateResult(...)` 现在同时接收 `isCacheHit`，并在一次更新里完成：

- 文本更新
- section 命中状态更新
- 布局计算

避免“先标记命中、再更新文本”带来的双次布局。

## 7. 闪动问题复盘与修复

### 7.1 根因

cache 命中场景出现闪动，主要由三点叠加：

- 命中标记与结果文本分两次 UI 更新。
- streaming 开启时，命中仍进入 streaming UI 状态切换。
- final 更新沿用动画逻辑。

### 7.2 修复

- 将 `isCacheHit` 合并进 `updateResult(...)` 单次更新。
- cache 命中时绕过 streaming UI 状态机，直接一次性 final 发布。
- cache 命中的 final 更新禁用动画（`shouldAnimate = false`）。

结果：

- 命中路径显著减少不必要重排。
- 减少“展示完成后再闪一下”的视觉抖动。

## 8. 主要变更文件

- `Sources/digger/Translation/TranslationDiskCache.swift`
- `Sources/digger/Translation/OpenAITranslator.swift`
- `Sources/digger/Selection/PopupFunctionRunner.swift`
- `Sources/digger/Preferences/AppPreferences.swift`
- `Sources/digger/Preferences/PreferencesViewModel.swift`
- `Sources/digger/Preferences/PreferencesView.swift`
- `Sources/digger/UI/ForceClickSelectionPopup.swift`
- `Sources/digger/UIStrings.swift`

## 9. 验证建议

### 9.1 构建验证

```bash
swift build
```

### 9.2 行为验证

1. 在 `Preferences > Cache` 设定较小容量与短 TTL。
2. 同一文本 + 同一 prompt 重复触发两次：第二次应命中缓存，且对应 section 显示命中图标。
3. 调整 prompt 或 model：应 miss 并重新请求 API。
4. 将 TTL 设置为极短并等待过期：再次请求应 miss。
5. 将容量设置为较小并产生多条缓存：观察旧项被回收。
6. 点击 `Open Cache Directory`：Finder 应打开缓存目录。

