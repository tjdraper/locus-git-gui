import Foundation

/// Calls `handler` for each notification posted, for as long as its owner keeps it. A listening
/// task that only held its owner weakly would stay suspended after the owner went away, along with
/// anything it captured, until the next notification, which for a view's own notifications never
/// comes.
final class NotificationWatch {
    private let listening: Task<Void, Never>

    init(_ name: Notification.Name, object: (AnyObject & Sendable)? = nil, handler: @escaping @MainActor () -> Void) {
        listening = Task { [weak object] in
            for await _ in NotificationCenter.default.notifications(named: name, object: object) {
                handler()
            }
        }
    }

    deinit {
        listening.cancel()
    }
}
