import Foundation

/// The fetch, pull or push the user started and how far it has got, for the bar above the history.
/// After a force push, the bar stays to name the commit the remote's branch was at, which is how to
/// put it back.
@Observable
final class RemoteProgress {
    struct Running {
        /// Such as “Pushing “main” to “origin””.
        let title: String
        var progress: GitProgress?
        let cancel: () -> Void
    }

    struct Notice: Equatable {
        let message: String
        /// The commit the notice names, which Copy Hash copies.
        let hash: String
    }

    private(set) var running: Running?
    private(set) var notice: Notice?

    func begin(_ title: String, cancel: @escaping () -> Void) {
        notice = nil
        running = Running(title: title, cancel: cancel)
    }

    func update(_ progress: GitProgress) {
        running?.progress = progress
    }

    func end() {
        running = nil
    }

    func show(_ notice: Notice) {
        self.notice = notice
    }

    func dismissNotice() {
        notice = nil
    }
}
