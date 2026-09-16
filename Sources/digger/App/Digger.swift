import AppKit
import Foundation

@main
struct Digger {
    static func main() {
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            // Run before normal startup so packaging never changes preferences or requests permissions.
            // Resolve the packaged resources explicitly; Bundle.module may fall back to the build tree.
            guard let bundleURL = Bundle.main.url(forResource: "digger_digger", withExtension: "bundle"),
                  let resources = Bundle(url: bundleURL),
                  let iconURL = resources.url(forResource: "AppIcon", withExtension: "icns"),
                  let icon = NSImage(contentsOf: iconURL), icon.isValid else {
                fatalError("Packaged app resources are missing or resolved outside the app")
            }
            print("Digger packaged startup and resources passed.")
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            PreviewMode.run()
            return
        }
        #endif
        StartOnLoginManager.refreshPreference()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let mainMenuController = MainMenuController()
        app.mainMenu = mainMenuController.buildMainMenu()
        let selectionHandler = SelectionHandler()
        let eventTap = GlobalShortcutMonitor(selectionHandler: selectionHandler)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--diagnose") {
            eventTap.start()
            print("[Digger] \(eventTap.statusDescription)")
            print("[Digger] Executable: \(Bundle.main.executablePath ?? CommandLine.arguments[0])")
            eventTap.stop()
            return
        }
        #endif
        weak var menuBarController: MenuBarController?
        let preferencesController = PreferencesWindowController(
            onPopupFontSizeChange: { newSize in
                selectionPopup.applyPopupTextSize(newSize)
            },
            onPopupOpacityChange: { newOpacity in
                selectionPopup.applyPopupOpacity(newOpacity)
            },
            onPopupLayoutChange: {
                selectionPopup.refreshLayout()
            },
            onLanguageChange: {
                selectionPopup.applyStrings()
                selectionPopup.refreshLayout()
                menuBarController?.refreshStrings()
                mainMenuController.applyStrings()
            },
            onCustomFunctionsChange: {}
        )
        selectionPopup.onOpenPreferences = {
            preferencesController.show()
        }
        let welcomeController = WelcomeWindowController()
        let appDelegate = AppDelegate(welcomeController: welcomeController)
        app.delegate = appDelegate
        welcomeController.onOpenPreferences = {
            preferencesController.show()
        }
        let menuController = MenuBarController(preferencesController: preferencesController, welcomeController: welcomeController)
        menuBarController = menuController

        menuController.shortcutStatus = { eventTap.statusDescription }
        // Register the hotkey even before Accessibility is granted, so it can explain what is missing.
        eventTap.start()
        welcomeController.onReady = { eventTap.start() }

        let firstLaunch = !AppPreferences.hasLaunchedBefore()
        AppPreferences.setHasLaunchedBefore(true)
        let needsAttention = PermissionChecker.needsAttention()
        let shouldShowWelcome = firstLaunch || needsAttention || !AppPreferences.skipWelcomeWhenReady()
        if shouldShowWelcome {
            welcomeController.show()
        }

        withExtendedLifetime(menuController) {
            withExtendedLifetime(eventTap) {
                withExtendedLifetime((welcomeController, appDelegate)) {
                    app.run()
                }
            }
        }
    }
}
