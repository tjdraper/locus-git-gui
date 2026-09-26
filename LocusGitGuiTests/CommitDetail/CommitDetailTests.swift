import Foundation
import Testing

struct CommitDetailTests {
    private func detail(of repository: FixtureRepository, _ revision: String = "HEAD") async throws -> CommitDetail {
        let hash = try await repository.git("rev-parse", revision)
        return try await CommitDetail.read(hash) { try await repository.run($0) }
    }

    @Test
    func aMessageThatIsOnlyASubjectHasNoBody() {
        // Act
        let body = CommitDetail.body(of: "Fix the parser\n")

        // Assert
        #expect(body == nil)
    }

    @Test
    func theBodyIsEverythingAfterTheFirstParagraph() {
        // Act
        let body = CommitDetail.body(of: "Fix the parser\nacross two lines\n\nIt was broken.\n\nTwice.\n\n")

        // Assert
        #expect(body == "It was broken.\n\nTwice.")
    }

    @Test
    func windowsLineEndingsStillSeparateTheBody() {
        // Act
        let body = CommitDetail.body(of: "Subject\r\n\r\nBody\r\n")

        // Assert
        #expect(body == "Body")
    }

    @Test
    func readsTheBodyFilesAndChangesOfACommit() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "one\ntwo\n", to: "kept.txt")
        try await repository.commit("Second", writing: "gone\n", to: "removed.txt")
        try repository.write("one\nTWO\n", to: "kept.txt")
        try repository.write("new\n", to: "é new.txt")
        try await repository.git("rm", "--quiet", "removed.txt")
        try await repository.git("add", "--all")
        try await repository.git("commit", "--quiet", "--message", "Third\n\nWith a body.")

        // Act
        let detail = try await detail(of: repository)

        // Assert
        #expect(detail.body == "With a body.")
        #expect(detail.files.map(\.path) == ["kept.txt", "removed.txt", "é new.txt"])
        #expect(detail.files.map(\.change) == [.modified, .deleted, .added])
        #expect(detail.patch.files.count == 3)
        #expect(detail.patch.files[0].map(\.kind) == [.hunkHeader, .context, .removed, .added])
        #expect(detail.patch.files[2].first == CommitPatchLine(kind: .fileInfo, text: "new file mode 100644"))
    }

    @Test
    func aRenameNamesWhereTheFileCameFrom() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Add", writing: "same contents\n", to: "old name.txt")
        try await repository.git("mv", "old name.txt", "new name.txt")
        try await repository.git("commit", "--quiet", "--message", "Rename")

        // Act
        let detail = try await detail(of: repository)

        // Assert
        #expect(detail.files == [ChangedFile(change: .renamed, path: "new name.txt", originalPath: "old name.txt")])
        #expect(detail.patch.files.first?.map(\.text).contains("rename from old name.txt") == true)
    }

    @Test
    func aRootCommitShowsTheFilesItAdded() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.git("config", "log.showRoot", "false")
        try await repository.commit("Root", writing: "a\n", to: "a.txt")

        // Act
        let detail = try await detail(of: repository)

        // Assert
        #expect(detail.files.map(\.path) == ["a.txt"])
        #expect(detail.patch.files.count == 1)
    }

    @Test
    func aMergeShowsWhatItBroughtIntoItsFirstParent() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Base", writing: "base\n", to: "base.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("Feature", writing: "feature\n", to: "feature.txt")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Main", writing: "main\n", to: "main.txt")
        try await repository.git("merge", "--quiet", "--no-ff", "--no-edit", "feature")

        // Act
        let detail = try await detail(of: repository)

        // Assert
        #expect(detail.files.map(\.path) == ["feature.txt"])
    }

    @Test
    func aFileReplacedByALinkIsOneFile() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Add", writing: "text\n", to: "a.txt")
        try repository.write("other\n", to: "b.txt")
        try FileManager.default.removeItem(at: repository.folder.appending(path: "a.txt"))
        try FileManager.default.createSymbolicLink(atPath: repository.folder.appending(path: "a.txt").path, withDestinationPath: "b.txt")
        try await repository.git("add", "--all")
        try await repository.git("commit", "--quiet", "--message", "Link")

        // Act
        let detail = try await detail(of: repository)

        // Assert
        #expect(detail.files.map(\.change) == [.typeChanged, .added])
        #expect(detail.patch.files.count == 2)
        #expect(detail.patch.files[0].contains(CommitPatchLine(kind: .added, text: "+b.txt")))
        #expect(detail.patch.files[1].contains(CommitPatchLine(kind: .added, text: "+other")))
    }
}
