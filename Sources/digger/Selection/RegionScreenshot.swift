import AppKit

/// Dim every display while choosing a region; Escape cancels without a request.
@MainActor
enum RegionScreenshot {
    static func capture() async throws -> Data? {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw CaptureError.permission
        }
        guard let region = await RegionPicker().select() else { return nil }
        // Let the compositor remove our overlays before reading screen pixels.
        try await Task.sleep(for: .milliseconds(120))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("digger-capture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("region.png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "png", "-R\(Int(region.minX)),\(Int(region.minY)),\(Int(region.width)),\(Int(region.height))", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard FileManager.default.fileExists(atPath: file.path) else { throw CaptureError.failed }
        guard status == 0 else { throw CaptureError.failed }
        let data = try Data(contentsOf: file)
        guard NSImage(data: data) != nil else { throw CaptureError.failed }
        return data
    }

    private enum CaptureError: LocalizedError {
        case permission, failed
        var errorDescription: String? {
            switch self {
            case .permission:
                localized("Allow Digger in System Settings → Privacy & Security → Screen Recording, then try again. You may need to restart Digger.",
                          "请在系统设置 → 隐私与安全性 → 屏幕录制中授权 Digger 后重试，可能需要重启 Digger。",
                          "システム設定 → プライバシーとセキュリティ → 画面収録で Digger を許可して再試行してください。再起動が必要な場合があります。")
            case .failed:
                localized("Could not read the screenshot. Please try again.", "无法读取截图，请重试。", "スクリーンショットを読み取れませんでした。再試行してください。")
            }
        }
    }
}

@MainActor
private final class RegionPicker {
    private var windows: [NSWindow] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?

    func select() async -> CGRect? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
            for screen in NSScreen.screens {
                let window = RegionPickerWindow(contentRect: screen.frame, styleMask: .borderless,
                                                backing: .buffered, defer: false)
                window.level = .screenSaver
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.isReleasedWhenClosed = false
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                let view = RegionPickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
                view.onFinish = { [self] rect in
                    let region = rect.map {
                        CGRect(x: screen.frame.minX + $0.minX,
                               y: desktopTop - screen.frame.minY - $0.maxY,
                               width: $0.width, height: $0.height).integral
                    }
                    finish(region)
                }
                window.contentView = view
                windows.append(window)
                window.orderFrontRegardless()
                if screen.frame.contains(NSEvent.mouseLocation) {
                    window.makeKey()
                    window.makeFirstResponder(view)
                }
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func finish(_ region: CGRect?) {
        for window in windows {
            (window.contentView as? RegionPickerView)?.onFinish = nil
            window.orderOut(nil)
        }
        windows.removeAll()
        continuation?.resume(returning: region)
        continuation = nil
    }
}

private final class RegionPickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class RegionPickerView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private(set) var selection: CGRect?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        let mask = NSBezierPath(rect: bounds)
        if let selection { mask.append(NSBezierPath(rect: selection)) }
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.42).setFill()
        mask.fill()
        if let selection {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        selection = Self.selectionRect(from: start, to: convert(event.locationInWindow, from: nil), bounds: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard let selection, selection.width >= 2, selection.height >= 2 else { return }
        onFinish?(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) }
    }

    static func selectionRect(from start: CGPoint, to end: CGPoint, bounds: CGRect) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
    }
}
