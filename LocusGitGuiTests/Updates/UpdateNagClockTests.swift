import Foundation
import Testing

struct UpdateNagClockTests {
    private let suiteName = "UpdateNagClockTests-\(UUID().uuidString)"

    private func makeDefaults() throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test
    func isOverdueTwoWeeksAfterTheFirstUpdateWasFound() throws {
        // Arrange
        let clock = try UpdateNagClock(defaults: makeDefaults(), appVersion: "2026.1")
        let found = Date(timeIntervalSince1970: 1_000_000)

        // Act
        clock.noteFound(at: found)
        clock.noteFound(at: found.addingTimeInterval(10 * 24 * 60 * 60))

        // Assert
        #expect(!clock.isOverdue(at: found.addingTimeInterval(13 * 24 * 60 * 60)))
        #expect(clock.isOverdue(at: found.addingTimeInterval(14 * 24 * 60 * 60)))
    }

    @Test
    func anUpdateInstalledSinceStartsTheClockAgain() throws {
        // Arrange
        let defaults = try makeDefaults()
        UpdateNagClock(defaults: defaults, appVersion: "2026.1").noteFound(at: Date(timeIntervalSince1970: 0))

        // Act
        let afterInstalling = UpdateNagClock(defaults: defaults, appVersion: "2026.2")

        // Assert
        #expect(afterInstalling.waitingSince == nil)
        #expect(!afterInstalling.isOverdue())
    }

    @Test
    func nothingIsOverdueWithoutAnUpdateFound() throws {
        // Arrange
        let clock = try UpdateNagClock(defaults: makeDefaults(), appVersion: "2026.1")

        // Assert
        #expect(!clock.isOverdue())
    }
}
