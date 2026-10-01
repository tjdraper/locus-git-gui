import Foundation

/// Which reviews the list shows, and in what order.
nonisolated enum ReviewListing {
    /// Older reviews are behind Show Older Reviews.
    static let recentDays = 90

    /// The most recently changed first.
    static func shown(_ reviews: [Review], at now: Date, includingOlder: Bool, calendar: Calendar = .current) -> [Review] {
        let cutoff = calendar.date(byAdding: .day, value: -recentDays, to: now) ?? now
        return reviews
            .filter { includingOlder || $0.lastOpened >= cutoff }
            .sorted { ($0.lastChanged, $0.created) > ($1.lastChanged, $1.created) }
    }

    static func olderCount(_ reviews: [Review], at now: Date, calendar: Calendar = .current) -> Int {
        let cutoff = calendar.date(byAdding: .day, value: -recentDays, to: now) ?? now
        return reviews.count { $0.lastOpened < cutoff }
    }
}
