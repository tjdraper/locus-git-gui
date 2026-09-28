import Foundation

/// The fetch, pull or push the user started and how far it has got, for the window's status. After
/// a force push, the status stays to name the commit the remote's branch was at, which is how to put
/// it back. While nothing runs, the status says when the repository last fetched.
@Observable
final class RemoteProgress {
    struct Running {
        /// Such as “Pushing “main” to “origin””.
        let title: String
        var progress: GitProgress?
        let cancel: () -> Void
        /// The toolbar shows the latest of what the window has to say.
        let started = Date.now
    }

    struct Notice: Equatable {
        let message: String
        /// The commit the notice names, which Copy Hash copies.
        let hash: String
        var shown = Date.now
    }

    private(set) var running: Running?
    private(set) var notice: Notice?
    /// The latest fetch the app knows of, from the app or from Terminal. Nil until one is known.
    private(set) var lastFetched: Date?
    /// Nil until the first refresh has read the remotes.
    private(set) var hasRemotes: Bool?

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

    /// Only ever moves later, since `FETCH_HEAD`'s time and the app's own fetches arrive separately.
    func noteFetched(at date: Date = .now) {
        guard lastFetched.map({ date > $0 }) ?? true else { return }
        lastFetched = date
    }

    func noteRemotes(exist: Bool) {
        guard hasRemotes != exist else { return }
        hasRemotes = exist
    }
}
