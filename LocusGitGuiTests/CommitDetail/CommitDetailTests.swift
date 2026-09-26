import Foundation
import Testing

struct CommitDetailTests {
    private func detail(of repository: FixtureRepository, _ revision: String = "HEAD") async throws -> CommitDetail {
        let hash = try await repository.git("rev-parse", revision)
        return try await CommitDetail.read(hash, options: DiffOptions()) {
            try await repository.run($0)
        } readingPatch: { command, limits in
            let result = try await repository.run(command)
            var parser = PatchParser(limits: limits)
            parser.consume(result.standardOutput)
            return (result, parser.finish())
        }
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
        #expect(detail.files.map(\.changed.path) == ["kept.txt", "removed.txt", "é new.txt"])
        #expect(detail.files.map(\.changed.change) == [.modified, .deleted, .added])
        #expect(detail.files[0].patch.hunks[0].lines.map(\.kind) == [.context, .removed, .added])
        #expect(detail.files[1].patch.removed == 1)
        #expect(detail.files[2].patch.hunks[0].lines.map(\.text) == ["new"])
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
        #expect(detail.files.map(\.changed.path) == ["new name.txt"])
        #expect(detail.files.map(\.changed.originalPath) == ["old name.txt"])
        #expect(detail.files[0].patch.fileLine == "diff --git a/old name.txt b/new name.txt")
        #expect(detail.files[0].patch.hunks.isEmpty)
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
        #expect(detail.files.map(\.changed.path) == ["a.txt"])
        #expect(detail.files[0].patch.added == 1)
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
        #expect(detail.files.map(\.changed.path) == ["feature.txt"])
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
        #expect(detail.files.map(\.changed.change) == [.typeChanged, .added])
        #expect(detail.files[0].patch.hunks.flatMap(\.lines).map(\.text) == ["text", "b.txt"])
        #expect(detail.files[1].patch.hunks.flatMap(\.lines).map(\.text) == ["other"])
    }

    @Test
    func aLeftOutFileIsReadOnItsOwn() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Add", writing: "one\n", to: "old.txt")
        try await repository.git("mv", "old.txt", "new.txt")
        try repository.write("one\ntwo\n", to: "new.txt")
        try await repository.git("add", "--all")
        try await repository.git("commit", "--quiet", "--message", "Rename and edit")
        let hash = try await repository.git("rev-parse", "HEAD")
        let changed = try await detail(of: repository).files[0].changed

        // Act
        let file = try await CommitDetail.readFile(changed, of: hash, options: DiffOptions()) { command, limits in
            let result = try await repository.run(command)
            var parser = PatchParser(limits: limits)
            parser.consume(result.standardOutput)
            return (result, parser.finish())
        }

        // Assert
        #expect(file.changed.change == .renamed)
        #expect(file.patch.hunks[0].lines.map(\.text) == ["one", "two"])
    }

    @Test
    func ignoringWhitespaceLeavesAFileWithNoHunks() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Add", writing: "a b\n", to: "a.txt")
        try await repository.commit("Add", writing: "one\n", to: "b.txt")
        try repository.write("a    b\n", to: "a.txt")
        try repository.write("two\n", to: "b.txt")
        try await repository.git("commit", "--quiet", "--all", "--message", "Spaces")
        let hash = try await repository.git("rev-parse", "HEAD")

        // Act
        var options = DiffOptions()
        options.ignoresWhitespace = true
        let detail = try await CommitDetail.read(hash, options: options) {
            try await repository.run($0)
        } readingPatch: { command, limits in
            let result = try await repository.run(command)
            var parser = PatchParser(limits: limits)
            parser.consume(result.standardOutput)
            return (result, parser.finish())
        }

        // Assert
        #expect(detail.files.map(\.changed.path) == ["a.txt", "b.txt"])
        #expect(detail.files[0].patch.hunks.isEmpty)
        #expect(detail.files[1].patch.hunks[0].lines.map(\.text) == ["one", "two"])
    }
}
