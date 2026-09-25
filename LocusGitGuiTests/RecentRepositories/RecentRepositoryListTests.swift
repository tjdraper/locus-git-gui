import Foundation
import Testing

struct RecentRepositoryListTests {
    private let suiteName = "RecentRepositoryListTests-\(UUID().uuidString)"

    private func makeDefaults() throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func repository(_ path: String, gitDirectory: String? = nil) -> Repository {
        Repository(
            workTree: URL(filePath: path, directoryHint: .isDirectory),
            gitDirectory: URL(filePath: gitDirectory ?? path + "/.git", directoryHint: .isDirectory)
        )
    }

    @Test
    func theLatestRepositoryComesFirst() {
        // Arrange
        var list = RecentRepositoryList()

        // Act
        list.note(repository("/work/website"))
        list.note(repository("/work/api"))

        // Assert
        #expect(list.entries.map(\.repository) == [repository("/work/api"), repository("/work/website")])
    }

    @Test
    func openingARepositoryAgainMovesItToTheTop() {
        // Arrange
        var list = RecentRepositoryList()
        list.note(repository("/work/website"))
        list.note(repository("/work/api"))

        // Act
        list.note(repository("/work/website/", gitDirectory: "/elsewhere/website.git"))

        // Assert
        #expect(list.entries.map(\.repository) == [
            repository("/work/website/", gitDirectory: "/elsewhere/website.git"),
            repository("/work/api"),
        ])
    }

    @Test
    func theOldestFallOffPastTheLimit() {
        // Arrange
        var list = RecentRepositoryList()

        // Act
        for number in 0...RecentRepositoryList.limit {
            list.note(repository("/work/\(number)"))
        }

        // Assert
        #expect(list.entries.count == RecentRepositoryList.limit)
        #expect(list.entries.map(\.repository).first == repository("/work/\(RecentRepositoryList.limit)"))
        #expect(list.entries.map(\.repository).last == repository("/work/1"))
    }

    @Test
    func removesARepository() {
        // Arrange
        var list = RecentRepositoryList()
        list.note(repository("/work/website"))
        list.note(repository("/work/api"))

        // Act
        list.remove([repository("/work/website")])

        // Assert
        #expect(list.entries.map(\.repository) == [repository("/work/api")])
    }

    @Test
    func openingARepositoryAgainKeepsItsDisplayName() {
        // Arrange
        var list = RecentRepositoryList()
        list.note(repository("/work/website"))
        list.setDisplayName("Marketing Site", for: repository("/work/website"))
        list.note(repository("/work/api"))

        // Act
        list.note(repository("/work/website"))

        // Assert
        #expect(list.entries.first?.displayName == "Marketing Site")
    }

    @Test
    func restoresRemovedRepositoriesWhereTheyWere() {
        // Arrange
        var list = RecentRepositoryList()
        for name in ["d", "c", "b", "a"] {
            list.note(repository("/work/\(name)"))
        }
        let original = list
        let removed = list.remove([repository("/work/b"), repository("/work/d")])

        // Act
        list.restore(removed)

        // Assert
        #expect(list == original)
    }

    @Test
    func aRestoredRepositoryOpenedSinceStaysWhereOpeningPutIt() {
        // Arrange
        var list = RecentRepositoryList()
        list.note(repository("/work/b"))
        list.note(repository("/work/a"))
        let removed = list.remove([repository("/work/b")])
        list.note(repository("/work/b"))

        // Act
        list.restore(removed)

        // Assert
        #expect(list.entries.map(\.repository) == [repository("/work/b"), repository("/work/a")])
    }

    @Test
    func readsAListSavedBeforeDisplayNames() throws {
        // Arrange
        let defaults = try makeDefaults()
        let saved = #"{"repositories":[{"workTree":"file:///work/website/","gitDirectory":"file:///work/website/.git/"}]}"#
        defaults.set(Data(saved.utf8), forKey: "RecentRepositories")

        // Act
        let read = RecentRepositoryList(defaults: defaults)

        // Assert
        #expect(read.entries == [RecentRepository(repository: repository("/work/website"), displayName: nil)])
    }

    @Test
    func survivesBeingSavedAndRead() throws {
        // Arrange
        let defaults = try makeDefaults()
        var list = RecentRepositoryList()
        list.note(repository("/work/website"))
        list.note(repository("/work/api"))
        list.setDisplayName("Marketing Site", for: repository("/work/website"))

        // Act
        list.save(to: defaults)
        let read = RecentRepositoryList(defaults: defaults)

        // Assert
        #expect(read == list)
    }

    @Test
    func anUnreadableListStartsOverEmpty() throws {
        // Arrange
        let defaults = try makeDefaults()
        defaults.set(Data("not a list".utf8), forKey: "RecentRepositories")

        // Act
        let read = RecentRepositoryList(defaults: defaults)

        // Assert
        #expect(read.entries.isEmpty)
    }
}
