import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSObject {
    private let window: NSWindow
    private let viewModel: PreferencesViewModel

    init(
        onPopupFontSizeChange: @escaping (CGFloat) -> Void,
        onPopupOpacityChange: @escaping (CGFloat) -> Void,
        onPopupLayoutChange: @escaping () -> Void,
        onLanguageChange: @escaping () -> Void,
        onCustomFunctionsChange: @escaping () -> Void
    ) {
        viewModel = PreferencesViewModel()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = UIStrings.Preferences.title
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 880, height: 620)
        window.center()
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        super.init()

        let rootView = PreferencesView(
            viewModel: viewModel,
            onPopupFontSizeChange: onPopupFontSizeChange,
            onPopupOpacityChange: onPopupOpacityChange,
            onPopupLayoutChange: onPopupLayoutChange,
            onLanguageChange: { [weak self] in
                self?.window.title = UIStrings.Preferences.title
                onLanguageChange()
            },
            onCustomFunctionsChange: onCustomFunctionsChange
        )
        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController
    }

    func show() {
        StartOnLoginManager.refreshPreference()
        viewModel.refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
