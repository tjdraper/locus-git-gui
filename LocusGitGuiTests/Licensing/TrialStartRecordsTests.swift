import Foundation
import Testing

struct TrialStartRecordsTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test
    func aFirstLaunchStartsTheTrialNowInBothPlaces() {
        // Act
        let settled = TrialStartRecords().settled(now: now)

        // Assert
        #expect(settled == .init(start: now, writesKeychain: true, writesCloud: true))
    }

    @Test
    func aReinstallKeepsTheKeychainsStartAndSendsItToICloud() {
        // Arrange
        let earlier = now.addingTimeInterval(-10 * TrialClock.day)

        // Act
        let settled = TrialStartRecords(keychain: earlier, cloud: nil).settled(now: now)

        // Assert
        #expect(settled == .init(start: earlier, writesKeychain: false, writesCloud: true))
    }

    @Test
    func aSecondMacTakesTheFirstOnesStart() {
        // Arrange
        let earlier = now.addingTimeInterval(-3 * TrialClock.day)

        // Act
        let settled = TrialStartRecords(keychain: nil, cloud: earlier).settled(now: now)

        // Assert
        #expect(settled == .init(start: earlier, writesKeychain: true, writesCloud: false))
    }

    @Test
    func theEarliestStartWins() {
        // Arrange
        let earlier = now.addingTimeInterval(-3 * TrialClock.day)
        let later = now.addingTimeInterval(-1 * TrialClock.day)

        // Act
        let fromCloud = TrialStartRecords(keychain: later, cloud: earlier).settled(now: now)
        let fromKeychain = TrialStartRecords(keychain: earlier, cloud: later).settled(now: now)

        // Assert
        #expect(fromCloud == .init(start: earlier, writesKeychain: true, writesCloud: false))
        #expect(fromKeychain == .init(start: earlier, writesKeychain: false, writesCloud: true))
    }

    @Test
    func startsThatAgreeWriteNothing() {
        // Arrange
        let earlier = now.addingTimeInterval(-3 * TrialClock.day)

        // Act
        let settled = TrialStartRecords(keychain: earlier, cloud: earlier).settled(now: now)

        // Assert
        #expect(settled == .init(start: earlier, writesKeychain: false, writesCloud: false))
    }
}
