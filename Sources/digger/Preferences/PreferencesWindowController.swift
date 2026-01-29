import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSObject {
    private let window: NSWindow
    private let viewModel: PreferencesViewModel

    init(
        onPopupFontSizeChange: @escaping (CGFloat) -> Void,
        onPopupLayoutChange: @escaping () -> Void,
        onLanguageChange: @escaping () -> Void,
        onForceClickSettingsChange: @escaping (Float, Float, TimeInterval) -> Void,
        onCustomFunctionsChange: @escaping () -> Void
    ) {
        AppPreferences.clearCustomFunctionsOnceIfNeeded()
        viewModel = PreferencesViewModel()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = UIStrings.Preferences.title
        window.isReleasedWhenClosed = false
        window.center()
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        super.init()

        let rootView = PreferencesView(
            viewModel: viewModel,
            onPopupFontSizeChange: onPopupFontSizeChange,
            onPopupLayoutChange: onPopupLayoutChange,
            onLanguageChange: { [weak self] in
                self?.window.title = UIStrings.Preferences.title
                onLanguageChange()
            },
            onForceClickSettingsChange: onForceClickSettingsChange,
            onCustomFunctionsChange: onCustomFunctionsChange
        )
        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController
    }

    func show() {
        viewModel.refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
