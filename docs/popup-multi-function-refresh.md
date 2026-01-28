# 多 function 场景下浮窗刷新防闪烁与滚动处理

本文档说明本次优化如何在多 function 并发更新时减少浮窗闪烁，同时保持内容持续更新，并移除自动滚动到底的逻辑。

## 背景问题

- 多个 function 同时流式输出时，每次更新都会触发布局与窗口尺寸变化，导致弹窗闪烁。
- 自动滚动到底在多 section 更新时会造成干扰，滚动位置跳动影响阅读。

## 实现目标

- **流畅更新**：内容持续刷新，不要卡成“只显示一行”。
- **减少闪烁**：合并短时间内的频繁布局更新，避免多次 setFrame。
- **不自动滚动**：保留当前滚动位置，不强制跳到底部。

## 核心实现

### 1) 布局更新节流

在 `ForceClickSelectionPopup` 中新增节流式布局更新：

- 首次更新立刻触发一次布局计算。
- 后续高频更新只在固定间隔内触发一次（默认 0.08s）。
- 通过 `layoutUpdateTimer` 合并多次刷新，避免“每个 token 都重算尺寸”。

关键逻辑：

```swift
private func scheduleLayoutUpdate(near location: CGPoint, animated: Bool)
```

该方法会记录最新的 `location` 与动画标记，并在计时器触发时统一更新窗口尺寸。

### 2) 跳过重复 setFrame

新增 `lastWindowFrame` 记录上一次的窗口 frame：

- 若新 frame 与旧 frame 的位置和大小差异小于阈值（0.5px），直接跳过更新。
- 避免“数据更新但尺寸几乎不变”导致的额外刷新闪烁。

关键逻辑：

```swift
private func setWindowFrame(contentSize: CGSize, near location: CGPoint, animated: Bool)
```

### 3) 取消自动滚动到底

移除 `layoutContent` 中的自动滚动逻辑：

- 不再重置 `scrollView.contentView` 到 bottom。
- 保持用户当前的滚动位置，避免多 function 结果频繁刷屏时的跳动。

## 相关代码位置

- `Sources/digger/UI/ForceClickSelectionPopup.swift`
  - `scheduleLayoutUpdate(near:animated:)`
  - `performPendingLayoutUpdate()`
  - `setWindowFrame(contentSize:near:animated:)`
  - `layoutContent(near:)` 中移除自动滚动逻辑

## 调整建议

如需更“稳”或更“跟手”的刷新体验，可调整节流间隔：

```swift
private let layoutDebounceInterval: TimeInterval = 0.08
```

- 较小数值：更新更及时，但刷新次数更多。
- 较大数值：更稳，但更新会略有延迟。
