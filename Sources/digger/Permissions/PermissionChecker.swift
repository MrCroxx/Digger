import AppKit
import ApplicationServices
import Foundation

struct PermissionStatus: Equatable {
    let accessibility: Bool
    let screenRecording: Bool

    var allGranted: Bool {
        accessibility && screenRecording
    }
}

enum PermissionChecker {
    static func currentStatus() -> PermissionStatus {
        let accessibilityGranted = AXIsProcessTrusted()
        return PermissionStatus(
            accessibility: accessibilityGranted,
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    static func needsAttention() -> Bool {
        // Text selection remains available without screenshot permission.
        !currentStatus().accessibility
    }
}

enum SystemPreferencesLinks {
    static func openAccessibility() {
        open(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openScreenRecording() {
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        open(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private static func open(urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
