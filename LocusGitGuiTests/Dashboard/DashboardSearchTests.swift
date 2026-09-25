import Foundation
import Testing

struct DashboardSearchTests {
    private func search(_ paths: String..., displayNames: [String: String] = [:]) -> DashboardSearch {
        DashboardSearch(entries: paths.map { path in
            RecentRepository(
                repository: Repository(
                    workTree: URL(filePath: path, directoryHint: .isDirectory),
                    gitDirectory: URL(filePath: path + "/.git", directoryHint: .isDirectory)
                ),
                displayName: displayNames[path]
            )
        })
    }

    private func names(_ search: DashboardSearch, _ query: String, boosts: [String: Double] = [:]) -> [String] {
        search.filter(query, among: { _ in true }, boosts: boosts).map(\.name)
    }

    @Test
    func aBlankSearchKeepsTheRecentOrder() {
        // Arrange
        let recent = search("/work/website", "/work/api", "/work/tools")

        // Act
        let filtered = names(recent, "  ")

        // Assert
        #expect(filtered == ["website", "api", "tools"])
    }

    @Test
    func leavesOutRepositoriesThatDoNotMatch() {
        // Arrange
        let recent = search("/work/website", "/work/api", "/work/tools")

        // Act
        let filtered = names(recent, "api")

        // Assert
        #expect(filtered == ["api"])
    }

    @Test
    func putsTheBestMatchFirst() {
        // Arrange
        let recent = search("/work/new-website", "/work/web")

        // Act
        let filtered = names(recent, "web")

        // Assert
        #expect(filtered == ["web", "new-website"])
    }

    @Test
    func equalMatchesKeepTheRecentOrder() {
        // Arrange
        let recent = search("/work/app-two", "/work/app-one")

        // Act
        let filtered = names(recent, "app")

        // Assert
        #expect(filtered == ["app-two", "app-one"])
    }

    @Test
    func matchesTheParentFoldersThatTellRepositoriesApart() {
        // Arrange
        let recent = search("/work/client/app", "/work/server/app")

        // Act
        let filtered = names(recent, "server")

        // Assert
        #expect(filtered == ["server/app"])
    }

    @Test
    func matchesADisplayNameAndTheFolderName() {
        // Arrange
        let recent = search("/work/mktg-2024", "/work/api", displayNames: ["/work/mktg-2024": "Marketing Site"])

        // Act
        let byDisplayName = names(recent, "marketing")
        let byFolderName = names(recent, "mktg")

        // Assert
        #expect(byDisplayName == ["Marketing Site"])
        #expect(byFolderName == ["Marketing Site"])
    }

    @Test
    func aRepositoryOpenedForTheSearchBeforeComesFirst() {
        // Arrange
        let recent = search("/work/web", "/work/new-website")

        // Act
        let filtered = names(recent, "web", boosts: ["/work/new-website": 1])

        // Assert
        #expect(filtered == ["new-website", "web"])
    }

    @Test
    func leavesOutRowsThatAreNotShown() {
        // Arrange
        let recent = search("/work/website", "/work/api")

        // Act
        let filtered = recent.filter("", among: { $0.name == "api" }, boosts: [:]).map(\.name)

        // Assert
        #expect(filtered == ["api"])
    }
}
