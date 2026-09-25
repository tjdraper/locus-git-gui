import Foundation
import Testing

struct AppCommandTests {
    @Test
    func noTwoCommandsShareAShortcut() {
        // Arrange
        let shortcuts = AppCommand.allCases.flatMap { [$0.shortcut, $0.alternateShortcut].compactMap(\.self) }

        // Act
        let distinct = Set(shortcuts)

        // Assert
        #expect(distinct.count == shortcuts.count)
    }

    @Test
    func countsTheRepositoriesADashboardCommandActsOn() {
        // Act
        let one = AppCommand.removeSelectedRepositories.title(count: 1)
        let three = AppCommand.removeSelectedRepositories.title(count: 3)

        // Assert
        #expect(one == "Remove Repository from List")
        #expect(three == "Remove 3 Repositories from List")
    }
}
