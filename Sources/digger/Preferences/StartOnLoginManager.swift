import Foundation
import ServiceManagement

enum StartOnLoginManager {
    static func isEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            return status == .enabled || status == .requiresApproval
        }
        return false
    }

    static func apply(enabled: Bool) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") { return }
        #endif
        guard #available(macOS 13.0, *) else {
            return
        }
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            print("Failed to update login item: \(error.localizedDescription)")
        }
    }

    static func refreshPreference() {
        let enabled = isEnabled()
        if AppPreferences.startOnLoginEnabled() != enabled {
            AppPreferences.setStartOnLoginEnabled(enabled)
        }
    }
}
