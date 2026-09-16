import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let welcomeController: WelcomeWindowController

    init(welcomeController: WelcomeWindowController) {
        self.welcomeController = welcomeController
        super.init()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        welcomeController.show()
        return false
    }
}
