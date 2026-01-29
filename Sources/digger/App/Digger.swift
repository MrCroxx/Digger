import AppKit
import Foundation
import OpenMultitouchSupport

private struct MainMenuReferences {
    let appMenuItem: NSMenuItem
    let quitItem: NSMenuItem
    let editMenuItem: NSMenuItem
    let editMenu: NSMenu
    let undoItem: NSMenuItem
    let redoItem: NSMenuItem
    let cutItem: NSMenuItem
    let copyItem: NSMenuItem
    let pasteItem: NSMenuItem
    let selectAllItem: NSMenuItem
    let windowMenuItem: NSMenuItem
    let windowMenu: NSMenu
    let closeItem: NSMenuItem
}

@main
struct Digger {
    @MainActor
    private static var mainMenuReferences: MainMenuReferences?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.mainMenu = buildMainMenu()
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
                selectionHandler.handleForceClick()
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
                applyMainMenuStrings()
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

    @MainActor
    private static func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(title: UIStrings.Menu.appTitle, action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(
            title: UIStrings.Menu.quit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem(title: UIStrings.Menu.edit, action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: UIStrings.Menu.edit)
        let undoItem = NSMenuItem(title: UIStrings.Menu.undo, action: #selector(UndoManager.undo), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: UIStrings.Menu.redo, action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(undoItem)
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        let cutItem = NSMenuItem(title: UIStrings.Menu.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copyItem = NSMenuItem(title: UIStrings.Menu.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let pasteItem = NSMenuItem(title: UIStrings.Menu.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let selectAllItem = NSMenuItem(title: UIStrings.Menu.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(cutItem)
        editMenu.addItem(copyItem)
        editMenu.addItem(pasteItem)
        editMenu.addItem(selectAllItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem(title: UIStrings.Menu.window, action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: UIStrings.Menu.window)
        let closeItem = NSMenuItem(
            title: UIStrings.Menu.close,
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenu.addItem(closeItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        mainMenuReferences = MainMenuReferences(
            appMenuItem: appMenuItem,
            quitItem: quitItem,
            editMenuItem: editMenuItem,
            editMenu: editMenu,
            undoItem: undoItem,
            redoItem: redoItem,
            cutItem: cutItem,
            copyItem: copyItem,
            pasteItem: pasteItem,
            selectAllItem: selectAllItem,
            windowMenuItem: windowMenuItem,
            windowMenu: windowMenu,
            closeItem: closeItem
        )

        return mainMenu
    }

    @MainActor
    private static func applyMainMenuStrings() {
        guard let refs = mainMenuReferences else {
            return
        }
        refs.appMenuItem.title = UIStrings.Menu.appTitle
        refs.quitItem.title = UIStrings.Menu.quit
        refs.editMenuItem.title = UIStrings.Menu.edit
        refs.editMenu.title = UIStrings.Menu.edit
        refs.undoItem.title = UIStrings.Menu.undo
        refs.redoItem.title = UIStrings.Menu.redo
        refs.cutItem.title = UIStrings.Menu.cut
        refs.copyItem.title = UIStrings.Menu.copy
        refs.pasteItem.title = UIStrings.Menu.paste
        refs.selectAllItem.title = UIStrings.Menu.selectAll
        refs.windowMenuItem.title = UIStrings.Menu.window
        refs.windowMenu.title = UIStrings.Menu.window
        refs.closeItem.title = UIStrings.Menu.close
    }
}
