import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let viewModel: WelcomeViewModel
    var onReady: (() -> Void)?
    var onOpenPreferences: (() -> Void)?

    override init() {
        viewModel = WelcomeViewModel()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        super.init()

        let rootView = WelcomeView(
            viewModel: viewModel,
            onOpenPreferences: { [weak self] in
                self?.onOpenPreferences?()
            },
            onStart: { [weak self] in
                self?.handleStart()
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController
        window.title = UIStrings.Welcome.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        viewModel.onStatusChange = { [weak self] status in
            guard status.allGranted else {
                return
            }
            self?.onReady?()
        }

    }

    func show() {
        viewModel.refresh()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        viewModel.canStart
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.stop()
    }

    private func handleStart() {
        guard viewModel.canStart else {
            return
        }
        AppPreferences.setWelcomeCompleted(true)
        viewModel.stop()
        window.orderOut(nil)
    }
}
