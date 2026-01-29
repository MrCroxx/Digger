import AppKit
import Foundation
import OpenMultitouchSupport

@main
struct Digger {
    static func main() {
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
        let menuController = MenuBarController(preferencesController: preferencesController)
        menuBarController = menuController

        Task {
            for await touches in manager.touchDataStream {
                monitor.update(touches: touches)
            }
        }

        if !manager.startListening() {
            print("Failed to start OpenMultitouchSupport listener.")
        }

        if !eventTap.start() {
            print("Failed to register event tap. Enable Accessibility permissions.")
        } else {
            print("Force click monitor started.")
        }

        withExtendedLifetime(menuController) {
            withExtendedLifetime(eventTap) {
                app.run()
            }
        }
    }
}
