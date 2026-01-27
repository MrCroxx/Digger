import ApplicationServices
import AppKit
import Carbon
import Foundation
import OpenMultitouchSupport
import os

private final class ForceClickMonitor {
    private let pressureThreshold: Float
    private let pressureDelta: Float
    private let baselineWindow: TimeInterval
    private let onForceClick: () -> Void
    private let activeLock = OSAllocatedUnfairLock<Bool>(uncheckedState: false)
    private let mouseDownLock = OSAllocatedUnfairLock<Bool>(uncheckedState: false)
    private let baselineLock = OSAllocatedUnfairLock<Float>(uncheckedState: 0)
    private let downTimeLock = OSAllocatedUnfairLock<TimeInterval?>(uncheckedState: nil)
    private var hasForceClicked = false

    init(
        pressureThreshold: Float,
        pressureDelta: Float,
        baselineWindow: TimeInterval,
        onForceClick: @escaping () -> Void
    ) {
        self.pressureThreshold = pressureThreshold
        self.pressureDelta = pressureDelta
        self.baselineWindow = baselineWindow
        self.onForceClick = onForceClick
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
            onForceClick()
        }
    }

    func shouldSuppressEvents() -> Bool {
        activeLock.withLockUnchecked { $0 }
    }
}

private final class ForceClickSelectionHandler {
    private let systemElement = AXUIElementCreateSystemWide()

    func handleForceClick() {
        guard let text = fetchOrSelectText(), !text.isEmpty else {
            if let fallbackText = copySelectionText(selectWordIfNeeded: true), !fallbackText.isEmpty {
                print(fallbackText)
            }
            return
        }
        print(text)
    }

    private func fetchOrSelectText() -> String? {
        guard let focusedElementValue = copyAttribute(
            element: systemElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ) else {
            return nil
        }
        let focusedElement = focusedElementValue as! AXUIElement

        var remainingNodes = 200
        if let selectedText = findSelectedText(in: focusedElement, maxDepth: 4, remainingNodes: &remainingNodes) {
            return selectedText
        }

        if let focusedWindowValue = copyAttribute(
            element: systemElement,
            attribute: kAXFocusedWindowAttribute as CFString
        ) {
            let focusedWindow = focusedWindowValue as! AXUIElement
            remainingNodes = 200
            if let selectedText = findSelectedText(in: focusedWindow, maxDepth: 4, remainingNodes: &remainingNodes) {
                return selectedText
            }
        }

        if let selectedText = copyAttribute(
            element: focusedElement,
            attribute: kAXSelectedTextAttribute as CFString
        ) as? String, !selectedText.isEmpty {
            return selectedText
        }

        guard let rangeValueAny = copyAttribute(
            element: focusedElement,
            attribute: kAXSelectedTextRangeAttribute as CFString
        ) else {
            return nil
        }
        let rangeValue = rangeValueAny as! AXValue

        var selectionRange = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &selectionRange) else {
            return nil
        }

        let selectionLocation = selectionRange.location
        var contextText: String?
        var contextBaseLocation = 0

        if let fullText = copyAttribute(
            element: focusedElement,
            attribute: kAXValueAttribute as CFString
        ) as? String, !fullText.isEmpty {
            contextText = fullText
            contextBaseLocation = 0
        } else if let visibleRangeValue = copyAttribute(
            element: focusedElement,
            attribute: kAXVisibleCharacterRangeAttribute as CFString
        ) {
            let axVisibleRange = visibleRangeValue as! AXValue
            var visibleRange = CFRange()
            if AXValueGetValue(axVisibleRange, .cfRange, &visibleRange),
               let visibleRangeValue = AXValueCreate(.cfRange, &visibleRange),
               let visibleText = copyParameterizedAttribute(
                   element: focusedElement,
                   attribute: kAXStringForRangeParameterizedAttribute as CFString,
                   parameter: visibleRangeValue
               ) as? String, !visibleText.isEmpty {
                contextText = visibleText
                contextBaseLocation = visibleRange.location
            }
        }

        guard let contextText, !contextText.isEmpty else {
            return nil
        }

        let nsContext = contextText as NSString
        let caretIndex = max(0, min(selectionLocation - contextBaseLocation, nsContext.length))
        let wordRange = currentWordRange(in: contextText, caretIndex: caretIndex)
        guard wordRange.length > 0 else {
            return nil
        }

        var adjustedRange = CFRange(
            location: contextBaseLocation + wordRange.location,
            length: wordRange.length
        )
        let axRange = AXValueCreate(.cfRange, &adjustedRange)
        if let axRange {
            let status = AXUIElementSetAttributeValue(
                focusedElement,
                kAXSelectedTextRangeAttribute as CFString,
                axRange
            )
            if status != AXError.success {
                return nil
            }
        }

        if let selectedText = copyAttribute(
            element: focusedElement,
            attribute: kAXSelectedTextAttribute as CFString
        ) as? String, !selectedText.isEmpty {
            return selectedText
        }

        if let axRange,
           let rangeText = copyParameterizedAttribute(
               element: focusedElement,
               attribute: kAXStringForRangeParameterizedAttribute as CFString,
               parameter: axRange
           ) as? String, !rangeText.isEmpty {
            return rangeText
        }

        return nsContext.substring(with: NSRange(location: wordRange.location, length: wordRange.length))
    }

    private func copySelectionText(selectWordIfNeeded: Bool) -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let changeCount = pasteboard.changeCount

        sendCopyCommand()
        Thread.sleep(forTimeInterval: 0.08)
        var copiedText = pasteboard.string(forType: .string)
        let didChange = pasteboard.changeCount != changeCount

        if (!didChange || copiedText?.isEmpty ?? true), selectWordIfNeeded {
            if let location = currentMouseLocation() {
                performDoubleClick(at: location)
                Thread.sleep(forTimeInterval: 0.06)
                sendCopyCommand()
                Thread.sleep(forTimeInterval: 0.08)
                copiedText = pasteboard.string(forType: .string)
            }
        }

        snapshot.restore(to: pasteboard)
        return copiedText
    }

    private func sendCopyCommand() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }

    private func currentMouseLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private func performDoubleClick(at location: CGPoint) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        for clickCount in 1...2 {
            let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: location,
                mouseButton: .left
            )
            let mouseUp = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: location,
                mouseButton: .left
            )
            mouseDown?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            mouseUp?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            mouseDown?.post(tap: .cgSessionEventTap)
            mouseUp?.post(tap: .cgSessionEventTap)
        }
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType[type] = data
                }
            }
            return dataByType
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { dataByType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dataByType {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}

private func findSelectedText(
    in element: AXUIElement,
    maxDepth: Int,
    remainingNodes: inout Int
) -> String? {
    if remainingNodes <= 0 {
        return nil
    }
    remainingNodes -= 1

    if let selectedText = copyAttribute(
        element: element,
        attribute: kAXSelectedTextAttribute as CFString
    ) as? String, !selectedText.isEmpty {
        return selectedText
    }

    if maxDepth == 0 {
        return nil
    }

    guard let children = copyAttribute(
        element: element,
        attribute: kAXChildrenAttribute as CFString
    ) as? [AXUIElement] else {
        return nil
    }

    for child in children {
        if let selectedText = findSelectedText(
            in: child,
            maxDepth: maxDepth - 1,
            remainingNodes: &remainingNodes
        ) {
            return selectedText
        }
    }

    return nil
}

private func copyAttribute(element: AXUIElement, attribute: CFString) -> AnyObject? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard result == .success else {
        return nil
    }
    return value
}

private func copyParameterizedAttribute(
    element: AXUIElement,
    attribute: CFString,
    parameter: AXValue
) -> AnyObject? {
    var value: AnyObject?
    let result = AXUIElementCopyParameterizedAttributeValue(element, attribute, parameter, &value)
    guard result == .success else {
        return nil
    }
    return value
}

private func currentWordRange(in text: String, caretIndex: Int) -> CFRange {
    let cfText = text as CFString
    let length = CFStringGetLength(cfText)
    if length == 0 {
        return CFRange(location: 0, length: 0)
    }

    let clampedIndex = max(0, min(caretIndex, length))
    let locale = Locale.current as CFLocale
    let tokenizer = CFStringTokenizerCreate(
        kCFAllocatorDefault,
        cfText,
        CFRange(location: 0, length: length),
        kCFStringTokenizerUnitWord,
        locale
    )

    CFStringTokenizerGoToTokenAtIndex(tokenizer, clampedIndex)
    var range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
    if range.location == kCFNotFound || range.length == 0, clampedIndex > 0 {
        CFStringTokenizerGoToTokenAtIndex(tokenizer, clampedIndex - 1)
        range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
    }

    if range.location == kCFNotFound || range.length == 0 {
        return CFRange(location: clampedIndex, length: 0)
    }

    return range
}

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

private final class ForceClickEventTap {
    private let controller: EventTapController
    private var runLoopSource: CFRunLoopSource?

    init(monitor: ForceClickMonitor) {
        controller = EventTapController(monitor: monitor)
    }

    func start() -> Bool {
        let mask = CGEventMask(
            (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.leftMouseUp.rawValue)
                | (1 << CGEventType.leftMouseDragged.rawValue)
        )

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(controller).toOpaque()
        ) else {
            return false
        }

        controller.tap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passRetained(event)
    }

    let controller = Unmanaged<EventTapController>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return controller.handle(event: event, type: type)
}

@main
struct Digger {
    static func main() {
        let manager = OMSManager.shared
        let thresholdText = ProcessInfo.processInfo.environment["FORCE_CLICK_PRESSURE_THRESHOLD"]
        let deltaText = ProcessInfo.processInfo.environment["FORCE_CLICK_PRESSURE_DELTA"]
        let windowText = ProcessInfo.processInfo.environment["FORCE_CLICK_BASELINE_WINDOW_MS"]
        let threshold = Float(thresholdText ?? "") ?? 3.0
        let delta = Float(deltaText ?? "") ?? 2.0
        let windowMs = Double(windowText ?? "") ?? 120
        let selectionHandler = ForceClickSelectionHandler()
        let monitor = ForceClickMonitor(
            pressureThreshold: threshold,
            pressureDelta: delta,
            baselineWindow: windowMs / 1000,
            onForceClick: {
                selectionHandler.handleForceClick()
            }
        )
        let eventTap = ForceClickEventTap(monitor: monitor)

        Task {
            for await touches in manager.touchDataStream {
                monitor.update(touches: touches)
            }
        }

        if !manager.startListening() {
            print("Failed to start OpenMultitouchSupport listener.")
        }

        if !eventTap.start() {
            print("Failed to register event tap. Enable Accessibility permissions.")
        } else {
            print("Force click monitor started.")
        }

        RunLoop.main.run()
        withExtendedLifetime(eventTap) {}
    }
}
