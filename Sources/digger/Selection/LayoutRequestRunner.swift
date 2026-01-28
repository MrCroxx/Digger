import Foundation

enum LayoutRequestRunner {
    static func start(_ context: LayoutExecutionContext) {
        Task.detached(priority: .userInitiated) {
            await ForceClickSelectionHandler.runLayoutRequests(context: context)
        }
    }
}
