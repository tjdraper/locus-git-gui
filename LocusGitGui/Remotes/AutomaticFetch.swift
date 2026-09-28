import Foundation

/// Fetches every remote now and then while the preference is on, and never asks for anything: a
/// question Git or SSH asks is declined, and what fails shows as the toolbar's quiet warning. Only
/// remote-tracking branches change (see `RemoteCommand.automaticFetch`).
final class AutomaticFetch {
    /// Soon after the window opens or the preference is turned on, so a repository opened in the
    /// morning is up to date without waiting a whole interval.
    private static let firstWait: Duration = .seconds(5)

    private let preferences: FetchPreferences
    private let fetch: () async -> Void
    private var loop: Task<Void, Never>?
    private var watching: Task<Void, Never>?
    private var current: Task<Void, Never>?
    private var lastFetched: ContinuousClock.Instant?
    private var isFetching = false

    init(preferences: FetchPreferences, fetch: @escaping () async -> Void) {
        self.preferences = preferences
        self.fetch = fetch
    }

    func start() {
        restartLoop()
        watching = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: FetchPreferences.automaticFetchDidChange) {
                self?.preferencesDidChange()
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

    /// A new interval counts from the last fetch. Before the first fetch, or during one, the loop
    /// reads the new interval itself once it next waits.
    private func preferencesDidChange() {
        guard preferences.fetchesAutomatically, loop != nil else {
            restartLoop()
            return
        }
        guard let lastFetched, !isFetching else { return }
        loop?.cancel()
        let sinceLast = ContinuousClock.now - lastFetched
        startLoop(firstWait: max(preferences.automaticInterval - sinceLast, Self.firstWait))
    }

    private func restartLoop() {
        loop?.cancel()
        current?.cancel()
        guard preferences.fetchesAutomatically else {
            loop = nil
            return
        }
        startLoop(firstWait: Self.firstWait)
    }

    private func startLoop(firstWait: Duration) {
        loop = Task { [weak self] in
            var wait = firstWait
            while !Task.isCancelled {
                try? await Task.sleep(for: wait)
                guard let self, !Task.isCancelled else { return }
                lastFetched = .now
                isFetching = true
                let fetching = Task { await self.fetch() }
                current = fetching
                await fetching.value
                isFetching = false
                wait = preferences.automaticInterval
            }
        }
    }
}
