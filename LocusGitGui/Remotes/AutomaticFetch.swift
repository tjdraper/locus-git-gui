import Foundation

/// Fetches every remote now and then while the preference is on, and never asks for anything: a
/// question Git or SSH asks is declined, and what fails shows as the toolbar's quiet warning. Only
/// remote-tracking branches change (see `RemoteCommand.automaticFetch`).
final class AutomaticFetch {
    /// Soon after the window opens or the preference is turned on, so a repository opened in the
    /// morning is up to date without waiting a whole interval.
    private static let firstWait: Duration = .seconds(5)
    private static let interval: Duration = .seconds(5 * 60)

    private let preferences: FetchPreferences
    private let fetch: () async -> Void
    private var loop: Task<Void, Never>?
    private var watching: Task<Void, Never>?
    private var current: Task<Void, Never>?

    init(preferences: FetchPreferences, fetch: @escaping () async -> Void) {
        self.preferences = preferences
        self.fetch = fetch
    }

    func start() {
        restartLoop()
        watching = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: FetchPreferences.automaticFetchDidChange) {
                self?.restartLoop()
            }
        }
    }

    func stop() {
        watching?.cancel()
        loop?.cancel()
        current?.cancel()
    }

    /// For the user's own fetch, pull or push, which this would only hold up.
    func cancelCurrent() {
        current?.cancel()
    }

    private func restartLoop() {
        loop?.cancel()
        current?.cancel()
        guard preferences.fetchesAutomatically else {
            loop = nil
            return
        }
        loop = Task { [weak self] in
            var wait = Self.firstWait
            while !Task.isCancelled {
                try? await Task.sleep(for: wait)
                guard let self, !Task.isCancelled else { return }
                let fetching = Task { await self.fetch() }
                current = fetching
                await fetching.value
                wait = Self.interval
            }
        }
    }
}
