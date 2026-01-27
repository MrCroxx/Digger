# Force Click Detection and Dictionary Suppression

本文档说明 `digger` 如何基于 `OpenMultitouchSupport` 监听触控板压力，识别 force click，并在触发时劫持系统字典弹窗行为，改为在终端输出日志。

## 背景与目标

`OpenMultitouchSupport` 封装了 macOS 私有 `MultitouchSupport.framework`，可以获取触控板每一帧的触控数据（位置、状态、压力、密度等）。

目标是：

- **感知 force click**：仅在用户“继续用力”的阶段触发日志。
- **劫持字典行为**：在 force click 时吞掉鼠标事件，避免触发系统字典弹窗。

## 实现概览

实现分为两部分：

1. **触控数据监听与 force click 判定**（`ForceClickMonitor`）
2. **事件 tap 与鼠标事件抑制**（`ForceClickEventTap`）

入口在 `Sources/digger/digger.swift`。

## Force Click 判定逻辑

核心原则：**普通点击只产生一次压力峰值，不应触发；force click 会在按下后继续加压，应触发。**

因此采用“基线 + 增量”的判定策略：

1. **按下期间采样基线压力**
   - `leftMouseDown` 发生后，在 `baselineWindow` 时间内收集最大压力作为基线。
2. **触发阈值**
   - 触发阈值为 `max(pressureThreshold, baseline + pressureDelta)`。
   - 只有当压力超过该阈值，才认为是 force click。
3. **一次按下只触发一次**
   - `hasForceClicked` 保证同一按压周期内只打印一次日志。

关键代码：

```swift
private final class ForceClickMonitor {
    private let pressureThreshold: Float
    private let pressureDelta: Float
    private let baselineWindow: TimeInterval
    private let activeLock = OSAllocatedUnfairLock<Bool>(uncheckedState: false)
    private let mouseDownLock = OSAllocatedUnfairLock<Bool>(uncheckedState: false)
    private let baselineLock = OSAllocatedUnfairLock<Float>(uncheckedState: 0)
    private let downTimeLock = OSAllocatedUnfairLock<TimeInterval?>(uncheckedState: nil)
    private var hasForceClicked = false

    init(pressureThreshold: Float, pressureDelta: Float, baselineWindow: TimeInterval) {
        self.pressureThreshold = pressureThreshold
        self.pressureDelta = pressureDelta
        self.baselineWindow = baselineWindow
    }

    func setMouseDown(_ isDown: Bool) {
        mouseDownLock.withLockUnchecked { $0 = isDown }
        if isDown {
            downTimeLock.withLockUnchecked { $0 = ProcessInfo.processInfo.systemUptime }
            baselineLock.withLockUnchecked { $0 = 0 }
            hasForceClicked = false
            activeLock.withLockUnchecked { $0 = false }
        } else {
            downTimeLock.withLockUnchecked { $0 = nil }
            baselineLock.withLockUnchecked { $0 = 0 }
            hasForceClicked = false
            activeLock.withLockUnchecked { $0 = false }
        }
    }

    func update(touches: [OMSTouchData]) {
        let isMouseDown = mouseDownLock.withLockUnchecked { $0 }
        if !isMouseDown {
            activeLock.withLockUnchecked { $0 = false }
            return
        }

        if hasForceClicked {
            activeLock.withLockUnchecked { $0 = true }
            return
        }

        guard let downTime = downTimeLock.withLockUnchecked({ $0 }) else {
            return
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - downTime
        var shouldTrigger = false

        for touch in touches {
            switch touch.state {
            case .making, .touching, .breaking, .lingering:
                if elapsed < baselineWindow {
                    baselineLock.withLockUnchecked { baseline in
                        if touch.pressure > baseline {
                            baseline = touch.pressure
                        }
                    }
                } else {
                    let baseline = baselineLock.withLockUnchecked { $0 }
                    let dynamicThreshold = max(pressureThreshold, baseline + pressureDelta)
                    if touch.pressure >= dynamicThreshold {
                        shouldTrigger = true
                    }
                }
            case .notTouching, .starting, .hovering, .leaving:
                break
            }
        }

        if shouldTrigger {
            hasForceClicked = true
            activeLock.withLockUnchecked { $0 = true }
            print("Force click detected")
        }
    }

    func shouldSuppressEvents() -> Bool {
        activeLock.withLockUnchecked { $0 }
    }
}
```

## 字典行为劫持逻辑

macOS 的字典弹窗由鼠标事件触发。为了阻止它，在 force click 发生时直接吞掉鼠标事件。

实现方式：使用 `CGEventTap` 在 `cghidEventTap` 层拦截鼠标事件，若 `ForceClickMonitor` 标记为 active，则返回 `nil`，即抑制该事件。

关键代码：

```swift
private final class EventTapController {
    var tap: CFMachPort?
    let monitor: ForceClickMonitor

    init(monitor: ForceClickMonitor) {
        self.monitor = monitor
    }

    func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .leftMouseDown:
            monitor.setMouseDown(true)
        case .leftMouseUp:
            monitor.setMouseDown(false)
        default:
            break
        }

        if monitor.shouldSuppressEvents() {
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}
```

## 运行流程

1. `OMSManager` 开启监听，异步获取触控数据。
2. `ForceClickMonitor` 根据压力变化判断是否 force click。
3. `CGEventTap` 拦截鼠标事件：
   - force click 发生时抑制事件，避免字典弹窗；
   - 同时在终端打印日志。

主入口：

```swift
let manager = OMSManager.shared
let monitor = ForceClickMonitor(
    pressureThreshold: threshold,
    pressureDelta: delta,
    baselineWindow: windowMs / 1000
)
let eventTap = ForceClickEventTap(monitor: monitor)

Task {
    for await touches in manager.touchDataStream {
        monitor.update(touches: touches)
    }
}

_ = manager.startListening()
_ = eventTap.start()
RunLoop.main.run()
```

## 配置项

可通过环境变量调整判定灵敏度：

- `FORCE_CLICK_PRESSURE_THRESHOLD`：最低触发压力，默认 `3.0`
- `FORCE_CLICK_PRESSURE_DELTA`：相对基线的最小增量，默认 `2.0`
- `FORCE_CLICK_BASELINE_WINDOW_MS`：基线采样窗口（毫秒），默认 `120`

示例：

```bash
FORCE_CLICK_PRESSURE_THRESHOLD=3.0 \
FORCE_CLICK_PRESSURE_DELTA=5.0 \
FORCE_CLICK_BASELINE_WINDOW_MS=150 \
swift run digger
```

## 重要注意事项

- `OpenMultitouchSupport` 使用私有框架，App Sandbox 需关闭。
- `CGEventTap` 需要 Accessibility 权限，否则无法注册。
- force click 判定依赖设备压力曲线，阈值需根据硬件进行调节。
