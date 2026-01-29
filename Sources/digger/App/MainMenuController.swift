import AppKit

@MainActor
final class MainMenuController {
    private struct MenuReferences {
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

    private var references: MenuReferences?

    func buildMainMenu() -> NSMenu {
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

        references = MenuReferences(
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

    func applyStrings() {
        guard let references else {
            return
        }
        references.appMenuItem.title = UIStrings.Menu.appTitle
        references.quitItem.title = UIStrings.Menu.quit
        references.editMenuItem.title = UIStrings.Menu.edit
        references.editMenu.title = UIStrings.Menu.edit
        references.undoItem.title = UIStrings.Menu.undo
        references.redoItem.title = UIStrings.Menu.redo
        references.cutItem.title = UIStrings.Menu.cut
        references.copyItem.title = UIStrings.Menu.copy
        references.pasteItem.title = UIStrings.Menu.paste
        references.selectAllItem.title = UIStrings.Menu.selectAll
        references.windowMenuItem.title = UIStrings.Menu.window
        references.windowMenu.title = UIStrings.Menu.window
        references.closeItem.title = UIStrings.Menu.close
    }
}
