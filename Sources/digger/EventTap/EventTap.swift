import AppKit
import ApplicationServices
import Carbon
import Foundation
import os

final class EventTapController {
    var tap: CFMachPort?
    let monitor: ForceClickMonitor
    private let selectionHandler: ForceClickSelectionHandler
    private static let focusStateLock = OSAllocatedUnfairLock<Bool>(uncheckedState: false)

    init(monitor: ForceClickMonitor, selectionHandler: ForceClickSelectionHandler) {
        self.monitor = monitor
        self.selectionHandler = selectionHandler
    }

    func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        Task { @MainActor in
            EventTapController.refreshFocusState()
        }
        let isPopupOrPreferencesFocused = EventTapController.focusStateLock.withLockUnchecked { $0 }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == CGKeyCode(kVK_Escape) {
                Task { @MainActor in
                    forceClickSelectionPopup.dismissOnEscape()
                }
            }
        case .leftMouseDown, .rightMouseDown:
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                forceClickSelectionPopup.dismissIfClickOutside(location)
            }
        default:
            break
        }

        switch type {
        case .leftMouseDown:
            selectionHandler.cacheSelectionBeforeMouseDown()
            monitor.setMouseDown(true)
        case .leftMouseUp:
            monitor.setMouseDown(false)
            selectionHandler.clearSelectionCache()
        default:
            break
        }

        if monitor.shouldSuppressEvents(), !isPopupOrPreferencesFocused {
            switch type {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown:
                return nil
            default:
                break
            }
        }

        return Unmanaged.passRetained(event)
    }

    @MainActor
    private static func refreshFocusState() {
        let isActive = NSApp.isActive
        guard let keyWindow = NSApp.keyWindow else {
            focusStateLock.withLockUnchecked { $0 = false }
            return
        }
        let responder = keyWindow.firstResponder as? NSView
        let isText = responder is NSTextView || responder is NSTextField
        focusStateLock.withLockUnchecked { $0 = isActive && isText }
    }
}

final class ForceClickEventTap {
    private let controller: EventTapController
    private var runLoopSource: CFRunLoopSource?

    init(monitor: ForceClickMonitor, selectionHandler: ForceClickSelectionHandler) {
        controller = EventTapController(monitor: monitor, selectionHandler: selectionHandler)
    }

    func start() -> Bool {
        let mask = CGEventMask(
            (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.leftMouseUp.rawValue)
                | (1 << CGEventType.leftMouseDragged.rawValue)
                | (1 << CGEventType.rightMouseDown.rawValue)
                | (1 << CGEventType.keyDown.rawValue)
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

func eventTapCallback(
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
