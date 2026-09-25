import Foundation
import Testing

struct FirstRunStatusTests {
    private let suiteName = "FirstRunStatusTests-\(UUID().uuidString)"

    private func makeDefaults() throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test
    func aFreshInstallIsPending() throws {
        // Arrange
        let status = try FirstRunStatus(defaults: makeDefaults())

        // Act
        let state = status.settleAtLaunch()

        // Assert
        #expect(state == .pending)
    }

    @Test
    func anInstallSparkleHasSeenIsAnExistingInstall() throws {
        // Arrange
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "SUHasLaunchedBefore")
        let status = FirstRunStatus(defaults: defaults)

        // Act
        let state = status.settleAtLaunch()

        // Assert
        #expect(state == .existingInstall)
    }

    @Test
    func staysPendingAfterSparkleStartsUntilCompleted() throws {
        // Arrange
        let defaults = try makeDefaults()
        let status = FirstRunStatus(defaults: defaults)
        _ = status.settleAtLaunch()
        defaults.set(true, forKey: "SUHasLaunchedBefore")

        // Act
        let relaunched = status.settleAtLaunch()
        status.markCompleted()
        let afterCompleting = status.settleAtLaunch()

        // Assert
        #expect(relaunched == .pending)
        #expect(afterCompleting == .completed)
    }
}
