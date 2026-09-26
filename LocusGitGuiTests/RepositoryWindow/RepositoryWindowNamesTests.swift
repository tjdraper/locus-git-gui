import Foundation
import Testing

struct RepositoryWindowNamesTests {
    private func repository(_ path: String, _ displayName: String? = nil) -> RepositoryWindowNames.Repository {
        RepositoryWindowNames.Repository(workTree: URL(filePath: path, directoryHint: .isDirectory), displayName: displayName)
    }

    @Test
    func aDisplayNameStandsInForTheFolder() {
        // Act
        let names = RepositoryWindowNames.make(for: [repository("/work/site", "Marketing Site"), repository("/work/api")])

        // Assert
        #expect(names == ["Marketing Site", "api"])
    }

    @Test
    func foldersWithTheSameNameAddTheirParentFolders() {
        // Act
        let names = RepositoryWindowNames.make(for: [repository("/work/client/app"), repository("/work/server/app")])

        // Assert
        #expect(names == ["client/app", "server/app"])
    }

    @Test
    func aFolderNamedLikeAnotherRepositorysDisplayNameAddsItsParentFolder() {
        // Act
        let names = RepositoryWindowNames.make(for: [repository("/work/client/app"), repository("/work/website", "app")])

        // Assert
        #expect(names == ["app", "app (website)"])
    }

    @Test
    func theSameDisplayNameTwiceAddsEachOnesFolders() {
        // Act
        let names = RepositoryWindowNames.make(for: [
            repository("/one/site", "Website"),
            repository("/two/site", "website"),
            repository("/work/api", "API"),
        ])

        // Assert
        #expect(names == ["Website (one/site)", "website (two/site)", "API"])
    }
}
