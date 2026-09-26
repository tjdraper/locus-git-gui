import Foundation
import Testing

struct WorkingAreaDiffTests {
    @Test
    func listsConflictsThenStagedThenUnstagedThenUntracked() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "one\n", to: "both.txt")
        try repository.write("two\n", to: "both.txt")
        try await repository.git("add", "both.txt")
        try repository.write("three\n", to: "both.txt")
        try repository.write("new\n", to: "new.txt")

        // Act
        let files = try await repository.workingArea()

        // Assert
        #expect(files.map(\.changed.path) == ["both.txt", "both.txt", "new.txt"])
        #expect(files.map(\.group) == [WorkingAreaGroup.staged, .unstaged, .untracked].map(\.rawValue))
        #expect(files[0].patch.hunks[0].lines.map(\.text) == ["one", "two"])
        #expect(files[1].patch.hunks[0].lines.map(\.text) == ["two", "three"])
        #expect(files[2].patch.hunks[0].lines.map(\.text) == ["new"])
    }

    @Test
    func aStagedFileHasItsObjectsForItsImages() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "one\n", to: "a.txt")
        let head = try await repository.git("rev-parse", "HEAD:a.txt")
        try repository.write("two\n", to: "a.txt")
        try await repository.git("add", "a.txt")
        let index = try await repository.git("rev-parse", ":a.txt")
        try repository.write("three\n", to: "a.txt")

        // Act
        let files = try await repository.workingArea()

        // Assert
        #expect(files[0].changed.oldObject == head)
        #expect(files[0].changed.newObject == index)
        #expect(files[1].changed.oldObject == index)
        #expect(files[1].changed.newObject == nil)
    }

    @Test
    func aStagedRenameKeepsWhereItCameFrom() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "same\n", to: "old name.txt")
        try await repository.git("mv", "old name.txt", "new name.txt")

        // Act
        let files = try await repository.workingArea()

        // Assert
        #expect(files.map(\.changed.change) == [.renamed])
        #expect(files[0].changed.originalPath == "old name.txt")
        #expect(files[0].patch.fileLine == "diff --git a/old name.txt b/new name.txt")
    }

    @Test
    func stagedChangesReadBeforeTheFirstCommit() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try repository.write("first\n", to: "a.txt")
        try await repository.git("add", "a.txt")

        // Act
        let files = try await repository.workingArea()

        // Assert
        #expect(files.map(\.changed.change) == [.added])
        #expect(files[0].patch.added == 1)
    }

    @Test
    func anUntrackedFileWithoutANewlineAtTheEndSaysSo() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\n", to: "a.txt")
        try repository.writeBytes("one\r\ntwo", to: "new.txt")

        // Act
        let file = try await repository.workingArea()[0]

        // Assert
        #expect(file.patch.hunks[0].lines.map(\.text) == ["one", "two"])
        #expect(file.patch.hunks[0].lines.map(\.newNumber) == [1, 2])
        #expect(file.patch.hunks[0].lines.last?.hasNoNewlineAtEnd == true)
        #expect(file.patch.added == 2)
    }

    @Test
    func anUntrackedBinaryFileIsntReadAsText() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\n", to: "a.txt")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01]).write(to: repository.folder.appending(path: "image.png"))

        // Act
        let file = try await repository.workingArea()[0]

        // Assert
        #expect(file.patch.isBinary)
        #expect(file.changed.isImage)
    }

    @Test
    func untrackedFilesPastTheLimitAreLeftOut() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\n", to: "a.txt")
        try repository.write(String(repeating: "line\n", count: 6000), to: "large.txt")

        // Act
        let file = try await repository.workingArea()[0]
        let whole = try await WorkingAreaDiff.readFile(
            file,
            options: DiffOptions(),
            workTree: repository.folder,
            readingPatch: repository.readPatch
        )

        // Assert
        #expect(file.patch.content == .tooLarge)
        #expect(file.patch.added == 6000)
        #expect(whole.patch.hunks[0].lines.count == 6000)
    }

    @Test
    func theRawPatchIsTheOneShown() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "one\r\ntwo\r\nthree\r\n", to: "a.txt")
        try repository.writeBytes("one\r\nTWO\r\nthree\r\nfour", to: "a.txt")
        try repository.write("new\n", to: "new.txt")
        let files = try await repository.workingArea()

        // Act
        let raws = try await files.asyncMap { file in
            try await WorkingAreaDiff.readRawPatch(of: file, options: DiffOptions(), workTree: repository.folder) {
                try await repository.run($0)
            }
        }

        // Assert
        #expect(zip(raws, files).allSatisfy { raw, file in raw?.matches(file.patch) == true })
    }
}

extension Sequence {
    func asyncMap<Value>(_ transform: (Element) async throws -> Value) async rethrows -> [Value] {
        var values: [Value] = []
        for element in self {
            values.append(try await transform(element))
        }
        return values
    }
}
