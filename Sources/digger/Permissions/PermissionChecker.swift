import AppKit
import ApplicationServices
import Foundation

struct PermissionStatus: Equatable {
    let accessibility: Bool

    var allGranted: Bool {
        accessibility
    }
}

enum PermissionChecker {
    static func currentStatus() -> PermissionStatus {
        let accessibilityGranted = AXIsProcessTrusted()
        return PermissionStatus(
            accessibility: accessibilityGranted
        )
    }

    static func needsAttention() -> Bool {
        !currentStatus().allGranted
    }
}

enum SystemPreferencesLinks {
    static func openAccessibility() {
        open(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openTrackpad() {
        open(urlString: "x-apple.systempreferences:com.apple.preference.trackpad?TrackpadPointing")
    }

    private static func open(urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
