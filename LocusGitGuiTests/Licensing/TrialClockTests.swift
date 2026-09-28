import Foundation
import Testing

struct TrialClockTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day = TrialClock.day

    @Test
    func theTrialEndsThirtyDaysAfterItStarts() {
        // Act
        let end = TrialClock.end(startedAt: start, now: start)

        // Assert
        #expect(end == start.addingTimeInterval(30 * day))
    }

    @Test
    func aPartOfADayCountsAsAWholeOne() {
        // Arrange
        let end = start.addingTimeInterval(30 * day)

        // Assert
        #expect(TrialClock.daysLeft(until: end, now: start) == 30)
        #expect(TrialClock.daysLeft(until: end, now: end.addingTimeInterval(-day - 1)) == 2)
        #expect(TrialClock.daysLeft(until: end, now: end.addingTimeInterval(-day)) == 1)
        #expect(TrialClock.daysLeft(until: end, now: end.addingTimeInterval(-1)) == 1)
        #expect(TrialClock.daysLeft(until: end, now: end) == 0)
        #expect(TrialClock.daysLeft(until: end, now: end.addingTimeInterval(day)) == 0)
    }

    @Test
    func anExpiredOverrideEndsTheTrialWhateverTheStart() {
        // Arrange
        let now = start.addingTimeInterval(day)

        // Act
        let end = TrialClock.end(startedAt: start, override: .expired, now: now)

        // Assert
        #expect(end < now)
    }

    @Test
    func aResetOverrideStartsTheTrialNow() {
        // Arrange
        let now = start.addingTimeInterval(100 * day)

        // Act
        let end = TrialClock.end(startedAt: start, override: .reset, now: now)

        // Assert
        #expect(end == now.addingTimeInterval(30 * day))
    }

    @Test
    func overridesAreReadFromTheLaunchArguments() {
        // Arrange
        let now = start

        // Assert
        #expect(TrialClock.Override(launchArguments: ["app", "--expire-trial"], now: now) == .expired)
        #expect(TrialClock.Override(launchArguments: ["app", "--reset-trial"], now: now) == .reset)
        #expect(TrialClock.Override(launchArguments: ["app", "--trial-ends-in", "90"], now: now) == .endsAt(now.addingTimeInterval(90)))
        #expect(TrialClock.Override(launchArguments: ["app", "--trial-ends-in"], now: now) == nil)
        #expect(TrialClock.Override(launchArguments: ["app"], now: now) == nil)
    }
}
