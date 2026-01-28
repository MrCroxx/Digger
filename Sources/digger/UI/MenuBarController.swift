import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let preferencesController: PreferencesWindowController
    private let menu: NSMenu
    private let preferencesItem: NSMenuItem
    private let quitItem: NSMenuItem

    init(preferencesController: PreferencesWindowController) {
        self.preferencesController = preferencesController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        preferencesItem = NSMenuItem(
            title: UIStrings.Menu.preferences,
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        quitItem = NSMenuItem(
            title: UIStrings.Menu.quit,
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        super.init()
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: UIStrings.Menu.appTitle)
            image?.isTemplate = true
            button.image = image
            button.toolTip = UIStrings.Menu.appTitle
        }

        preferencesItem.target = self
        menu.addItem(preferencesItem)
        menu.addItem(.separator())

        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func refreshStrings() {
        preferencesItem.title = UIStrings.Menu.preferences
        quitItem.title = UIStrings.Menu.quit
        if let button = statusItem.button {
            button.toolTip = UIStrings.Menu.appTitle
        }
    }

    @objc private func openPreferences() {
        preferencesController.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
