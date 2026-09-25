import Foundation

/// Turns a burst of file changes into one refresh. A build writing thousands of files costs one
/// refresh once it goes quiet, and one every few seconds if it never does.
final class RefreshScheduler {
    enum Reason: String {
        case windowOpened
        case filesChanged
        case windowBecameKey
        case retried
    }

    private static let quietPeriod: Duration = .milliseconds(400)
    private static let longestWait: Duration = .seconds(3)

    private let refresh: (Reason) async -> Void
    private var pending: Task<Void, Never>?
    private var firstRequest: ContinuousClock.Instant?

    init(refresh: @escaping (Reason) async -> Void) {
        self.refresh = refresh
    }

    func requestSoon(because reason: Reason) {
        let now = ContinuousClock.now
        let first = firstRequest ?? now
        firstRequest = first
        schedule(at: min(now + Self.quietPeriod, first + Self.longestWait), because: reason)
    }

    func requestNow(because reason: Reason) {
        schedule(at: .now, because: reason)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        firstRequest = nil
    }

    /// A refresh already running is cancelled rather than waited for, since what it would show is
    /// already out of date.
    private func schedule(at deadline: ContinuousClock.Instant, because reason: Reason) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(until: deadline)
            guard !Task.isCancelled, let self else { return }
            firstRequest = nil
            await refresh(reason)
        }
    }
}
