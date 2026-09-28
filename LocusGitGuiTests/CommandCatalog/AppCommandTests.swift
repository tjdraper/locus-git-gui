import AppKit
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
    func theCopyPathCommandsSwapShortcutsWhenOptionCommandCCopiesThePathFromTheRoot() {
        // Act
        let absolute = AppCommand.copyAbsolutePath.shortcut(optionCommandCCopiesPathFromRoot: true)
        let fromRoot = AppCommand.copyPathFromRepositoryRoot.shortcut(optionCommandCCopiesPathFromRoot: true)
        let other = AppCommand.copyCommitHash.shortcut(optionCommandCCopiesPathFromRoot: true)

        // Assert
        #expect(fromRoot == KeyShortcut("c", [.command, .option]))
        #expect(absolute == KeyShortcut("c", [.command, .option, .shift]))
        #expect(other == AppCommand.copyCommitHash.shortcut)
        #expect(AppCommand.copyAbsolutePath.shortcut(optionCommandCCopiesPathFromRoot: false) == AppCommand.copyAbsolutePath.shortcut)
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
