import Foundation
import Testing

/// Each test picks lines as the working area would and hands the patch to the real `git apply`.
struct PartialPatchTests {
    private func file(_ group: WorkingAreaGroup, _ path: String, in repository: FixtureRepository) async throws -> DiffFile {
        try #require(try await repository.workingArea().first { $0.group == group.rawValue && $0.changed.path == path })
    }

    private func apply(
        _ lines: Set<Int>,
        of file: DiffFile,
        in repository: FixtureRepository,
        direction: PartialPatch.Direction,
        toIndex: Bool
    ) async throws {
        let raw = try #require(try await WorkingAreaDiff.readRawPatch(of: file, options: DiffOptions(), workTree: repository.folder) {
            try await repository.run($0)
        })
        #expect(raw.matches(file.patch))
        let patch = try #require(PartialPatch.make(from: raw, hunk: 0, lines: lines, path: file.changed.path, direction: direction))
        try await WorkingAreaStaging.apply(patch, toIndex: toIndex, reverse: direction == .reverse, contextLines: 3) {
            try await repository.run($0)
        }
    }

    @Test
    func stagesOnlyThePickedLines() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\nb\nc\n", to: "f.txt")
        try repository.write("a\nB\nc\nd\n", to: "f.txt")
        let file = try await file(.unstaged, "f.txt", in: repository)
        // a, -b, +B, c, +d
        let added = 4

        // Act
        try await apply([added], of: file, in: repository, direction: .forward, toIndex: true)

        // Assert
        #expect(try await repository.staged("f.txt") == "a\nb\nc\nd\n")
        #expect(try repository.contents(of: "f.txt") == "a\nB\nc\nd\n")
    }

    @Test
    func stagingARemovedLineAloneKeepsTheLineThatReplacedItOut() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\nb\nc\n", to: "f.txt")
        try repository.write("a\nB\nc\n", to: "f.txt")
        let file = try await file(.unstaged, "f.txt", in: repository)

        // Act
        try await apply([1], of: file, in: repository, direction: .forward, toIndex: true)

        // Assert
        #expect(try await repository.staged("f.txt") == "a\nc\n")
    }

    @Test
    func unstagesOnlyThePickedLines() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\nb\nc\n", to: "f.txt")
        try repository.write("a\nB\nc\nd\n", to: "f.txt")
        try await repository.git("add", "f.txt")
        let file = try await file(.staged, "f.txt", in: repository)

        // Act: the -b and +B pair.
        try await apply([1, 2], of: file, in: repository, direction: .reverse, toIndex: true)

        // Assert
        #expect(try await repository.staged("f.txt") == "a\nb\nc\nd\n")
    }

    @Test
    func discardsOnlyThePickedLinesFromTheFile() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\nb\nc\n", to: "f.txt")
        try repository.write("a\nB\nc\nd\n", to: "f.txt")
        let file = try await file(.unstaged, "f.txt", in: repository)

        // Act: the added d.
        try await apply([4], of: file, in: repository, direction: .reverse, toIndex: false)

        // Assert
        #expect(try repository.contents(of: "f.txt") == "a\nB\nc\n")
        #expect(try await repository.staged("f.txt") == "a\nb\nc\n")
    }

    @Test
    func stagesSomeLinesOfAnUntrackedFileAsANewFile() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\n", to: "a.txt")
        try repository.write("one\ntwo\nthree\n", to: "new.txt")
        let file = try await file(.untracked, "new.txt", in: repository)

        // Act
        try await apply([0, 2], of: file, in: repository, direction: .forward, toIndex: true)

        // Assert
        #expect(try await repository.staged("new.txt") == "one\nthree\n")
    }

    @Test
    func unstagesSomeLinesOfAStagedNewFileAndKeepsTheFile() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\n", to: "a.txt")
        try repository.write("one\ntwo\nthree\n", to: "new.txt")
        try await repository.git("add", "new.txt")
        let file = try await file(.staged, "new.txt", in: repository)

        // Act
        try await apply([1], of: file, in: repository, direction: .reverse, toIndex: true)

        // Assert
        #expect(try await repository.staged("new.txt") == "one\nthree\n")
    }

    @Test
    func keepsWindowsLineEndings() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try repository.writeBytes("a\r\nb\r\nc\r\n", to: "f.txt")
        try await repository.git("add", "f.txt")
        try await repository.git("commit", "--quiet", "--message", "First")
        try repository.writeBytes("a\r\nB\r\nc\r\nd\r\n", to: "f.txt")
        let file = try await file(.unstaged, "f.txt", in: repository)

        // Act
        try await apply([4], of: file, in: repository, direction: .forward, toIndex: true)

        // Assert
        #expect(try await repository.staged("f.txt") == "a\r\nb\r\nc\r\nd\r\n")
    }

    @Test
    func aLastLineWithoutANewlineStaysThatWay() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\nb\n", to: "f.txt")
        try repository.writeBytes("A\nb\nc", to: "f.txt")
        let file = try await file(.unstaged, "f.txt", in: repository)
        let lines = file.patch.hunks[0].lines
        let addedC = try #require(lines.firstIndex { $0.kind == .added && $0.text == "c" })

        // Act
        try await apply([addedC], of: file, in: repository, direction: .forward, toIndex: true)

        // Assert
        #expect(try await repository.staged("f.txt") == "a\nb\nc")
    }

    @Test
    func worksWithNoUnchangedLinesAroundTheChanges() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\nb\nc\nd\ne\n", to: "f.txt")
        try repository.write("a\nB\nc\nd\nE\n", to: "f.txt")
        var options = DiffOptions()
        options.contextLines = 0
        let file = try #require(try await repository.workingArea(options: options).first)
        let raw = try #require(try await WorkingAreaDiff.readRawPatch(of: file, options: options, workTree: repository.folder) {
            try await repository.run($0)
        })
        let patch = try #require(PartialPatch.make(from: raw, hunk: 1, lines: [0, 1], path: "f.txt", direction: .forward))

        // Act
        try await WorkingAreaStaging.apply(patch, toIndex: true, reverse: false, contextLines: 0) { try await repository.run($0) }

        // Assert
        #expect(try await repository.staged("f.txt") == "a\nb\nc\nd\nE\n")
    }

    /// Git gives an empty side the line before it as its start, which is easy to be one line off from.
    private func applyWithoutContext(
        _ picked: Set<Int>,
        hunk: Int,
        in repository: FixtureRepository,
        direction: PartialPatch.Direction,
        toIndex: Bool
    ) async throws {
        var options = DiffOptions()
        options.contextLines = 0
        let file = try #require(try await repository.workingArea(options: options).first)
        let raw = try #require(try await WorkingAreaDiff.readRawPatch(of: file, options: options, workTree: repository.folder) {
            try await repository.run($0)
        })
        let patch = try #require(PartialPatch.make(from: raw, hunk: hunk, lines: picked, path: "f.txt", direction: direction))
        try await WorkingAreaStaging.apply(patch, toIndex: toIndex, reverse: direction == .reverse, contextLines: 0) {
            try await repository.run($0)
        }
    }

    @Test
    func stagesPartOfAnInsertionWithNoUnchangedLinesAround() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\nb\nc\nd\ne\n", to: "f.txt")
        try repository.write("a\nb\nc\nX\nY\nd\nE\n", to: "f.txt")

        // Act: X alone, from `@@ -3,0 +4,2 @@`.
        try await applyWithoutContext([0], hunk: 0, in: repository, direction: .forward, toIndex: true)

        // Assert
        #expect(try await repository.staged("f.txt") == "a\nb\nc\nX\nd\ne\n")
    }

    @Test
    func discardsPartOfADeletionWithNoUnchangedLinesAround() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\nb\nc\nd\ne\n", to: "f.txt")
        try repository.write("a\nd\ne\n", to: "f.txt")

        // Act: put c back, from `@@ -2,2 +1,0 @@`.
        try await applyWithoutContext([1], hunk: 0, in: repository, direction: .reverse, toIndex: false)

        // Assert
        #expect(try repository.contents(of: "f.txt") == "a\nc\nd\ne\n")
    }

    @Test
    func aPickWithNoChangedLinesMakesNoPatch() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a\nb\nc\n", to: "f.txt")
        try repository.write("a\nB\nc\n", to: "f.txt")
        let file = try await file(.unstaged, "f.txt", in: repository)
        let raw = try #require(try await WorkingAreaDiff.readRawPatch(of: file, options: DiffOptions(), workTree: repository.folder) {
            try await repository.run($0)
        })

        // Act
        let patch = PartialPatch.make(from: raw, hunk: 0, lines: [0], path: "f.txt", direction: .forward)

        // Assert
        #expect(patch == nil)
    }

    @Test
    func quotesAPathAPatchCantHoldAsItIs() {
        // Act
        let quoted = GitPatchPath.quoted("a/tab\there \"quoted\"")

        // Assert
        #expect(quoted == "\"a/tab\\there \\\"quoted\\\"\"")
    }
}
