import Foundation

/// Whether the app may change repositories, and until when. One date covers the trial now and a
/// license once there is one, so everything that asks only compares it with the time.
nonisolated struct Entitlement: Equatable {
    enum Reason: Equatable {
        /// The trial's start hasn't been read yet. Counts as entitled, or every launch would open
        /// locked for a moment.
        case checking
        case trial
    }

    let reason: Reason
    /// Nil for no end.
    let until: Date?

    static let checking = Entitlement(reason: .checking, until: nil)

    static func trial(startedAt start: Date, override: TrialClock.Override? = nil, now: Date) -> Entitlement {
        Entitlement(reason: .trial, until: TrialClock.end(startedAt: start, override: override, now: now))
    }

    func isEntitled(at now: Date) -> Bool {
        until.map { now < $0 } ?? true
    }

    /// Nil when there's no trial counting down.
    func trialDaysLeft(at now: Date) -> Int? {
        guard reason == .trial, let until else { return nil }
        return TrialClock.daysLeft(until: until, now: now)
    }

    /// The next moment what the app shows about this changes: the next time the days left go down
    /// by one, which on the last day is the end itself. Nil when nothing will change.
    func nextChange(after now: Date) -> Date? {
        guard let until, now < until else { return nil }
        let remainder = until.timeIntervalSince(now).truncatingRemainder(dividingBy: TrialClock.day)
        return now.addingTimeInterval(remainder > 0 ? remainder : TrialClock.day)
    }
}
