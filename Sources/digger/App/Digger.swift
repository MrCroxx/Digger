import AppKit
import Foundation

@main
struct Digger {
    static func main() {
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
                withExtendedLifetime(welcomeController) {
                    app.run()
                }
            }
        }
    }
}
