import Combine
import Foundation

@MainActor
final class WelcomeViewModel: ObservableObject {
    @Published private(set) var status: PermissionStatus
    @Published private(set) var canStart: Bool
    @Published var skipWelcomeWhenReady: Bool {
        didSet {
            AppPreferences.setSkipWelcomeWhenReady(skipWelcomeWhenReady)
        }
    }
    @Published var startOnLogin: Bool {
        didSet {
            applyStartOnLoginChange()
        }
    }

    var onStatusChange: ((PermissionStatus) -> Void)?

    private var timer: Timer?
    private var isApplyingStartOnLogin = false

    init() {
        let current = PermissionChecker.currentStatus()
        status = current
        canStart = current.allGranted
        skipWelcomeWhenReady = AppPreferences.skipWelcomeWhenReady()
        startOnLogin = AppPreferences.startOnLoginEnabled()
        startPolling()
    }

    func refresh() {
        let current = PermissionChecker.currentStatus()
        if current != status {
            status = current
            canStart = current.allGranted
            onStatusChange?(current)
        } else {
            canStart = current.allGranted
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func applyStartOnLoginChange() {
        if isApplyingStartOnLogin {
            return
        }
        isApplyingStartOnLogin = true
        AppPreferences.setStartOnLoginEnabled(startOnLogin)
        StartOnLoginManager.apply(enabled: startOnLogin)
        let currentValue = StartOnLoginManager.isEnabled()
        if currentValue != startOnLogin {
            AppPreferences.setStartOnLoginEnabled(currentValue)
            startOnLogin = currentValue
        }
        isApplyingStartOnLogin = false
    }

    deinit {}
}
