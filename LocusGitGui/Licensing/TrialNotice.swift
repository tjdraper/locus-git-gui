import Foundation

/// What the app says about the trial: how long is left for the whole of it, and then that it has
/// ended, each with a way to buy. It grows more urgent as the end nears, so the lock never arrives
/// unannounced.
nonisolated enum TrialNotice: Equatable {
    case running(daysLeft: Int)
    case ended

    enum Urgency: Comparable {
        case none
        case low
        case medium
        case high
    }

    /// Nil while the trial's start is still being read.
    static func current(for entitlement: Entitlement, now: Date) -> TrialNotice? {
        guard entitlement.isEntitled(at: now) else { return .ended }
        return entitlement.trialDaysLeft(at: now).map { .running(daysLeft: $0) }
    }

    var message: String {
        switch self {
        case let .running(daysLeft):
            daysLeft == 1 ? "1 day left in your trial." : "\(daysLeft) days left in your trial."
        case .ended:
            "Your trial has ended. Changing a repository needs a license."
        }
    }

    var urgency: Urgency {
        switch self {
        case .ended: .high
        case let .running(daysLeft) where daysLeft <= 1: .high
        case let .running(daysLeft) where daysLeft <= 5: .medium
        case let .running(daysLeft) where daysLeft <= 15: .low
        case .running: .none
        }
    }
}
