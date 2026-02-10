# Popup 流式性能与布局优化（本次 Session）

本文档汇总本次 session 对 pop-up 的实现优化，目标是：

1. 提升流式输出阶段的流畅度，减少“卡卡的”体感。
2. 在保证可读性的同时，增加轻量淡入过渡。
3. 降低长文本流式时的 UI 抖动与主线程开销。
4. 将弹窗布局调整为“优先横向扩展，不够再纵向扩展/滚动”。

## 背景与根因

卡顿主要来自两类叠加开销：

1. **高频全量布局**  
   流式阶段每次更新都可能触发完整 `layoutContent(...)`，其中包含多段文本测量与窗口 frame 变更。

2. **全量文本替换**  
   流式更新以“整段字符串覆盖”的方式写回 UI，文本越长，每次更新越重。

## 改动概览

### 1) 布局与动画节流

- 为流式阶段使用独立布局节流窗口，降低重排频率。
- 仅在全部分区都完成后再做窗口动画，避免多分区完成时反复动画。
- 若文本内容与状态未变化，则跳过后续布局与按钮刷新路径。

实现位置：
- `Sources/digger/UI/ForceClickSelectionPopup.swift`
  - `updateResult(...)`
  - `scheduleLayoutUpdate(...)`
  - `performPendingLayoutUpdate()`

### 2) 文本测量缓存

- 新增文本测量缓存，按 `revision + width + font` 复用测量结果。
- 文本未变化时，不重复做 `boundingRect` 或 layout manager 测量。

实现位置：
- `Sources/digger/UI/ForceClickSelectionPopup.swift`
  - `TextMeasurementCacheEntry`
  - `measuredTextSize(...)`
  - `takeNextTextRevision()`

### 3) 流式淡入过渡（加速版）

- 在流式文本更新时应用轻量 fade 过渡。
- 动画参数已调快，减少拖尾体感：
  - `streamingFadeInterval = 0.08`
  - `streamingFadeDuration = 0.08`

实现位置：
- `Sources/digger/UI/ForceClickSelectionPopup.swift`
  - `applyStreamingFadeIfNeeded(...)`

### 4) 流式刷新频率优化

- 调整流式 flush 参数，平衡实时性与 UI 压力：
  - `updateInterval: 0.033`
  - `minFlushCharacters: 72`

实现位置：
- `Sources/digger/Selection/PopupFunctionRunner.swift`
  - `runStreaming(...)`

### 5) 增量 append（NSTextStorage）

这是本次针对长文本流式抖动的核心优化。

- function result 展示控件从 `NSTextField` 迁移为 `NSTextView`。
- 更新时优先执行“前缀增量”策略：
  - 若 `incoming` 以 `current` 为前缀，仅 append 差量。
  - 否则回退整段替换（保证正确性）。
- append 直接走 `textStorage.append(...)`，避免每次重设整段文本。

实现位置：
- `Sources/digger/UI/ForceClickSelectionPopup.swift`
  - `FunctionSection`（`textView`）
  - `updateFunctionSection(...)`
  - `streamingDelta(...)`
  - `appendResultText(...)`
  - `replaceResultText(...)`

### 6) 拖动/选中文本交互兼容

- 因 result 控件改为 `NSTextView`，点击命中逻辑同步支持可选择 `NSTextView`，避免“想选中文本却触发拖窗”。

实现位置：
- `Sources/digger/UI/ForceClickSelectionPopup.swift`
  - `DraggableScrollView.findSelectableTextView(...)`

### 7) 布局策略改为“横向优先”

- `layoutContent(...)` 改为先按 `maxWidthLimit` 测量，优先用宽度换高度。
- 仅当此时高度仍超限，再进入纵向受限与滚动逻辑。
- 不再使用“高度超限后按步进逐步加宽”的路径。

实现位置：
- `Sources/digger/UI/ForceClickSelectionPopup.swift`
  - `layoutContent(...)`

## 实现原理（简版）

1. **减少每次更新的工作量**：  
   通过“节流 + 跳过无变化更新 + 测量缓存”压缩主线程负载。

2. **减少每次更新的数据量**：  
   通过 `NSTextStorage` 增量 append，避免长文本重复整段赋值。

3. **控制视觉开销**：  
   淡入动画做节流且缩短时长，保持顺滑但不拖慢节奏。

4. **优化空间分配策略**：  
   先横向扩展，降低换行带来的垂直增长，再在必要时滚动。

## 验证

### 编译验证

```bash
swift build
```

### 交互验证建议

1. 触发 pop-up，多分区同时流式返回，观察是否仍有明显卡顿。
2. 在长文本输出场景，确认文本滚动更新更平滑、跳变减少。
3. 验证淡入体感是否“快且自然”（无明显拖尾）。
4. 验证窗口宽度行为：优先横向扩展，超限后再出现纵向滚动。
5. 在结果区尝试文本选择，确认不会误触窗口拖动。
