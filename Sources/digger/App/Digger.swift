import AppKit
import Foundation
import OpenMultitouchSupport

@main
struct Digger {
    static func main() {
        StartOnLoginManager.refreshPreference()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let mainMenuController = MainMenuController()
        app.mainMenu = mainMenuController.buildMainMenu()
        let manager = OMSManager.shared
        let threshold = Float(AppPreferences.pressureThreshold())
        let delta = Float(AppPreferences.pressureDelta())
        let windowMs = Double(AppPreferences.baselineWindowMs())
        let selectionHandler = ForceClickSelectionHandler()
        let monitor = ForceClickMonitor(
            pressureThreshold: threshold,
            pressureDelta: delta,
            baselineWindow: windowMs / 1000,
            onForceClick: {
                Task {
                    await selectionHandler.handleForceClick()
                }
            }
        )
        let eventTap = ForceClickEventTap(monitor: monitor, selectionHandler: selectionHandler)
        weak var menuBarController: MenuBarController?
        let preferencesController = PreferencesWindowController(
            onPopupFontSizeChange: { newSize in
                forceClickSelectionPopup.applyPopupTextSize(newSize)
            },
            onPopupOpacityChange: { newOpacity in
                forceClickSelectionPopup.applyPopupOpacity(newOpacity)
            },
            onPopupLayoutChange: {
                forceClickSelectionPopup.refreshLayout()
            },
            onLanguageChange: {
                forceClickSelectionPopup.applyStrings()
                forceClickSelectionPopup.refreshLayout()
                menuBarController?.refreshStrings()
                mainMenuController.applyStrings()
            },
            onForceClickSettingsChange: { newThreshold, newDelta, newWindow in
                monitor.updateSettings(
                    pressureThreshold: newThreshold,
                    pressureDelta: newDelta,
                    baselineWindow: newWindow
                )
            },
            onCustomFunctionsChange: {}
        )
        forceClickSelectionPopup.onOpenPreferences = {
            preferencesController.show()
        }
        let welcomeController = WelcomeWindowController()
        welcomeController.onOpenPreferences = {
            preferencesController.show()
        }
        let menuController = MenuBarController(preferencesController: preferencesController, welcomeController: welcomeController)
        menuBarController = menuController

        Task {
            for await touches in manager.touchDataStream {
                monitor.update(touches: touches)
            }
        }

        if !manager.startListening() {
            print("Failed to start OpenMultitouchSupport listener.")
        }

        var eventTapStarted = false
        let startEventTapIfNeeded = {
            guard !eventTapStarted else {
                return
            }
            guard !PermissionChecker.needsAttention() else {
                return
            }
            if !eventTap.start() {
                print("Failed to register event tap. Enable Accessibility permissions.")
            } else {
                print("Force click monitor started.")
                eventTapStarted = true
            }
        }
        welcomeController.onReady = {
            startEventTapIfNeeded()
        }
        startEventTapIfNeeded()

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
