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
        #expect(list.repositories == [repository("/work/api"), repository("/work/website")])
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
        #expect(list.repositories == [
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
        #expect(list.repositories.count == RecentRepositoryList.limit)
        #expect(list.repositories.first == repository("/work/\(RecentRepositoryList.limit)"))
        #expect(list.repositories.last == repository("/work/1"))
    }

    @Test
    func removesARepository() {
        // Arrange
        var list = RecentRepositoryList()
        list.note(repository("/work/website"))
        list.note(repository("/work/api"))

        // Act
        list.remove(repository("/work/website"))

        // Assert
        #expect(list.repositories == [repository("/work/api")])
    }

    @Test
    func survivesBeingSavedAndRead() throws {
        // Arrange
        let defaults = try makeDefaults()
        var list = RecentRepositoryList()
        list.note(repository("/work/website"))
        list.note(repository("/work/api"))

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
        #expect(read.repositories.isEmpty)
    }
}
