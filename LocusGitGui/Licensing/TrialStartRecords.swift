import Foundation

/// The trial's start as each place that keeps it has it. The Keychain outlasts deleting the app, and
/// iCloud reaches the user's other Macs, so neither a reinstall nor a second Mac starts a new trial.
nonisolated struct TrialStartRecords: Equatable {
    var keychain: Date?
    var cloud: Date?

    struct Settled: Equatable {
        let start: Date
        /// The places that don't have the start yet, or have a later one.
        let writesKeychain: Bool
        let writesCloud: Bool
    }

    /// The earliest start wins. Two Macs that start before iCloud has reached either then settle on
    /// the same one, whichever hears from the other first. With none kept anywhere, the trial starts
    /// now.
    func settled(now: Date) -> Settled {
        let start = [keychain, cloud].compactMap(\.self).min() ?? now
        return Settled(start: start, writesKeychain: keychain != start, writesCloud: cloud != start)
    }
}
