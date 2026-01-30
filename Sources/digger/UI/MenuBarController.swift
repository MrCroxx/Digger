import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let preferencesController: PreferencesWindowController
    private let welcomeController: WelcomeWindowController
    private let menu: NSMenu
    private let openWelcomeItem: NSMenuItem
    private let preferencesItem: NSMenuItem
    private let quitItem: NSMenuItem

    init(preferencesController: PreferencesWindowController, welcomeController: WelcomeWindowController) {
        self.preferencesController = preferencesController
        self.welcomeController = welcomeController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        openWelcomeItem = NSMenuItem(
            title: UIStrings.Menu.openWelcome,
            action: #selector(openWelcome),
            keyEquivalent: ""
        )
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
        openWelcomeItem.target = self
        menu.addItem(openWelcomeItem)
        menu.addItem(preferencesItem)
        menu.addItem(.separator())

        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func refreshStrings() {
        openWelcomeItem.title = UIStrings.Menu.openWelcome
        preferencesItem.title = UIStrings.Menu.preferences
        quitItem.title = UIStrings.Menu.quit
        if let button = statusItem.button {
            button.toolTip = UIStrings.Menu.appTitle
        }
    }

    @objc private func openPreferences() {
        preferencesController.show()
    }

    @objc private func openWelcome() {
        welcomeController.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
