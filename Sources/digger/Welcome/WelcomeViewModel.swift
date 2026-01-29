import Combine
import Foundation

@MainActor
final class WelcomeViewModel: ObservableObject {
    @Published private(set) var status: PermissionStatus
    @Published private(set) var canStart: Bool

    var onStatusChange: ((PermissionStatus) -> Void)?

    private var timer: Timer?

    init() {
        let current = PermissionChecker.currentStatus()
        status = current
        canStart = current.allGranted
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

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {}
}
