import Foundation

/// Whether the setup checklist opens at launch.
nonisolated struct FirstRunStatus {
    enum State: String {
        case pending
        case completed
        /// Installed before the checklist existed, so the user already went through each setup
        /// step as the app asked for it.
        case existingInstall
    }

    private static let defaultsKey = "FirstRunState"
    private static let sparkleLaunchedBeforeKey = "SUHasLaunchedBefore"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var state: State? {
        defaults.string(forKey: Self.defaultsKey).flatMap(State.init)
    }

    /// Has to run before Sparkle starts, because Sparkle's launched-before flag is what tells an
    /// install from before the checklist apart from a fresh one. The answer is stored, so the
    /// relaunch after moving to Applications still opens the checklist.
    func settleAtLaunch() -> State {
        if let state {
            return state
        }
        let state: State = defaults.bool(forKey: Self.sparkleLaunchedBeforeKey) ? .existingInstall : .pending
        defaults.set(state.rawValue, forKey: Self.defaultsKey)
        return state
    }

    func markCompleted() {
        defaults.set(State.completed.rawValue, forKey: Self.defaultsKey)
    }
}
