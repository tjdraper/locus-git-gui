import Foundation
import Testing

struct EntitlementTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day = TrialClock.day

    @Test
    func stillCheckingCountsAsEntitled() {
        // Assert
        #expect(Entitlement.checking.isEntitled(at: start))
        #expect(Entitlement.checking.trialDaysLeft(at: start) == nil)
        #expect(Entitlement.checking.nextChange(after: start) == nil)
    }

    @Test
    func aTrialIsEntitledUntilItEnds() {
        // Arrange
        let entitlement = Entitlement.trial(startedAt: start, now: start)
        let end = start.addingTimeInterval(30 * day)

        // Assert
        #expect(entitlement.isEntitled(at: end.addingTimeInterval(-1)))
        #expect(!entitlement.isEntitled(at: end))
    }

    @Test
    func theNextChangeIsWhenTheDaysLeftGoDown() {
        // Arrange
        let entitlement = Entitlement.trial(startedAt: start, now: start)
        let now = start.addingTimeInterval(3 * 60 * 60)

        // Act
        let next = entitlement.nextChange(after: now)

        // Assert
        #expect(next == start.addingTimeInterval(day))
        #expect(entitlement.trialDaysLeft(at: now) == 30)
        #expect(entitlement.trialDaysLeft(at: start.addingTimeInterval(day)) == 29)
    }

    @Test
    func onTheLastDayTheNextChangeIsTheEnd() {
        // Arrange
        let entitlement = Entitlement.trial(startedAt: start, now: start)
        let end = start.addingTimeInterval(30 * day)

        // Assert
        #expect(entitlement.nextChange(after: end.addingTimeInterval(-60)) == end)
        #expect(entitlement.nextChange(after: end) == nil)
    }
}
