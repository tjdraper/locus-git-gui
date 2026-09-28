import Foundation

/// When the trial ends and how many days are left, from when it started.
nonisolated enum TrialClock {
    static let length: TimeInterval = 30 * day
    static let day: TimeInterval = 24 * 60 * 60

    /// A Debug build's stand-in for the stored start, from its launch arguments. It changes only the
    /// sums: the start is kept in iCloud, so writing a made-up one there would reach every Mac on the
    /// same Apple ID, release builds included.
    enum Override: Equatable {
        /// As if the trial had just ended.
        case expired
        /// As if the trial had just started.
        case reset
        /// As if the trial ends then, to see the countdown's stages and the lock arriving with the
        /// app open. A date rather than a length, since the clock is read again and again, and a
        /// length counted from each reading would never run out.
        case endsAt(Date)

        /// `--expire-trial`, `--reset-trial`, or `--trial-ends-in` and a number of seconds.
        init?(launchArguments arguments: [String], now: Date) {
            if arguments.contains("--expire-trial") {
                self = .expired
            } else if arguments.contains("--reset-trial") {
                self = .reset
            } else if let index = arguments.firstIndex(of: "--trial-ends-in"),
                      let seconds = arguments.dropFirst(index + 1).first.flatMap(TimeInterval.init) {
                self = .endsAt(now.addingTimeInterval(seconds))
            } else {
                return nil
            }
        }
    }

    static func end(startedAt start: Date, override: Override? = nil, now: Date) -> Date {
        switch override {
        case .expired: now.addingTimeInterval(-1)
        case .reset: now.addingTimeInterval(length)
        case let .endsAt(date): date
        case nil: start.addingTimeInterval(length)
        }
    }

    /// A part of a day counts as a whole one, so the last day is “1 day left” rather than none.
    /// Zero once it has ended.
    static func daysLeft(until end: Date, now: Date) -> Int {
        max(0, Int((end.timeIntervalSince(now) / day).rounded(.up)))
    }
}
