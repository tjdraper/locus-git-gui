import Foundation
import Testing

struct DashboardSearchTests {
    private func rows(_ paths: String...) -> [DashboardRow] {
        DashboardRow.rows(for: paths.map { path in
            Repository(
                workTree: URL(filePath: path, directoryHint: .isDirectory),
                gitDirectory: URL(filePath: path + "/.git", directoryHint: .isDirectory)
            )
        })
    }

    @Test
    func aBlankSearchKeepsTheRecentOrder() {
        // Arrange
        let recent = rows("/work/website", "/work/api", "/work/tools")

        // Act
        let filtered = DashboardSearch.filter(recent, by: "  ")

        // Assert
        #expect(filtered == recent)
    }

    @Test
    func leavesOutRepositoriesThatDoNotMatch() {
        // Arrange
        let recent = rows("/work/website", "/work/api", "/work/tools")

        // Act
        let filtered = DashboardSearch.filter(recent, by: "api")

        // Assert
        #expect(filtered.map(\.name) == ["api"])
    }

    @Test
    func putsTheBestMatchFirst() {
        // Arrange
        let recent = rows("/work/new-website", "/work/web")

        // Act
        let filtered = DashboardSearch.filter(recent, by: "web")

        // Assert
        #expect(filtered.map(\.name) == ["web", "new-website"])
    }

    @Test
    func equalMatchesKeepTheRecentOrder() {
        // Arrange
        let recent = rows("/work/app-two", "/work/app-one")

        // Act
        let filtered = DashboardSearch.filter(recent, by: "app")

        // Assert
        #expect(filtered.map(\.name) == ["app-two", "app-one"])
    }

    @Test
    func matchesTheParentFoldersThatTellRepositoriesApart() {
        // Arrange
        let recent = rows("/work/client/app", "/work/server/app")

        // Act
        let filtered = DashboardSearch.filter(recent, by: "server")

        // Assert
        #expect(filtered.map(\.name) == ["server/app"])
    }
}
