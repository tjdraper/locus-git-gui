import Foundation
import Testing

struct TrialNoticeTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day = TrialClock.day

    private func notice(daysLeft: Double) -> TrialNotice? {
        TrialNotice.current(for: .trial(startedAt: start, now: start), now: start.addingTimeInterval((30 - daysLeft) * day))
    }

    @Test
    func theWholeTrialCountsDown() {
        // Act
        let notice = notice(daysLeft: 30)

        // Assert
        #expect(notice == .running(daysLeft: 30))
        #expect(notice?.message == "30 days left in your trial.")
        #expect(self.notice(daysLeft: 0.5)?.message == "1 day left in your trial.")
    }

    @Test
    func growsMoreUrgentAsTheEndNears() {
        // Assert
        #expect(notice(daysLeft: 16)?.urgency == TrialNotice.Urgency.none)
        #expect(notice(daysLeft: 15)?.urgency == .low)
        #expect(notice(daysLeft: 6)?.urgency == .low)
        #expect(notice(daysLeft: 5)?.urgency == .medium)
        #expect(notice(daysLeft: 2)?.urgency == .medium)
        #expect(notice(daysLeft: 1)?.urgency == .high)
        #expect(notice(daysLeft: 0)?.urgency == .high)
    }

    @Test
    func anEndedTrialSaysSo() {
        // Assert
        #expect(notice(daysLeft: 0) == .ended)
        #expect(notice(daysLeft: -40) == .ended)
    }

    @Test
    func nothingShowsWhileChecking() {
        // Act
        let notice = TrialNotice.current(for: .checking, now: start)

        // Assert
        #expect(notice == nil)
    }
}
