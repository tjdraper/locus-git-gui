import Foundation
import Testing

struct ConflictFileContentsTests {
    @Test
    func aConflictInTheLinesIsEditable() async throws {
        // Arrange
        let repository = try await FixtureRepository.mergeStoppedOnConflict(base: "a\n", main: "main\n", feature: "feature\n")
        defer { repository.remove() }

        // Act
        let contents = try await repository.conflictContents("notes.txt")

        // Assert
        #expect(contents.isEditable)
        #expect(contents.base == .text("a\n"))
        #expect(contents.ours == .text("main\n"))
        #expect(contents.theirs == .text("feature\n"))
        #expect(contents.result.text?.contains("<<<<<<< HEAD\nmain\n=======\nfeature\n>>>>>>> feature\n") == true)
        #expect(contents.markerSize == 7)
    }

    @Test
    func aFileBothSidesAddedHasNoAncestor() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Start", writing: "start\n", to: "start.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("Feature", writing: "feature\n", to: "new.txt")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Main", writing: "main\n", to: "new.txt")
        _ = try await repository.run(.changing(["merge", "--no-edit", "feature"]))

        // Act
        let contents = try await repository.conflictContents("new.txt")

        // Assert
        #expect(contents.base == .absent)
        #expect(contents.isEditable)
    }

    @Test
    func aFileDeletedOnOneSideIsAChoiceOfVersions() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Base", writing: "a\n", to: "notes.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.git("rm", "--quiet", "notes.txt")
        try await repository.git("commit", "--quiet", "--message", "Delete")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Main", writing: "main\n", to: "notes.txt")
        _ = try await repository.run(.changing(["merge", "--no-edit", "feature"]))

        // Act
        let contents = try await repository.conflictContents("notes.txt")

        // Assert
        #expect(!contents.isEditable)
        #expect(contents.theirs == .absent)
        #expect(ConflictVersionChoice.choices(for: contents.stages) == [.ours, .delete])
    }

    @Test
    func aBinaryFileIsntText() async throws {
        // Arrange
        let repository = try await FixtureRepository.mergeStoppedOnConflict(
            path: "image.bin",
            base: "a\0",
            main: "main\0",
            feature: "feature\0"
        )
        defer { repository.remove() }

        // Act
        let contents = try await repository.conflictContents("image.bin")

        // Assert
        #expect(contents.ours == .notText)
        #expect(!contents.isEditable)
        #expect(ConflictVersionChoice.choices(for: contents.stages) == [.ours, .theirs])
    }

    @Test
    func theMarkerSizeComesFromTheAttribute() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try repository.write("*.txt conflict-marker-size=12\n", to: ".gitattributes")
        try await repository.git("add", ".gitattributes")
        try await repository.git("commit", "--quiet", "--message", "Attributes")
        try await repository.commit("Base", writing: "a\n", to: "notes.txt")
        try await repository.git("switch", "--quiet", "--create", "feature")
        try await repository.commit("Feature", writing: "feature\n", to: "notes.txt")
        try await repository.git("switch", "--quiet", "main")
        try await repository.commit("Main", writing: "main\n", to: "notes.txt")
        _ = try await repository.run(.changing(["merge", "--no-edit", "feature"]))

        // Act
        let contents = try await repository.conflictContents("notes.txt")

        // Assert
        #expect(contents.markerSize == 12)
        let markers = ConflictMarkers(parsing: try #require(contents.result.text), markerSize: contents.markerSize)
        #expect(markers.conflicts.count == 1)
    }

    @Test
    func savingKeepsTheFileExecutable() throws {
        // Arrange
        let repository = try FixtureRepository(folder: TestGit.makeScratchFolder())
        defer { repository.remove() }
        try repository.write("#!/bin/sh\n", to: "run.sh")
        let path = repository.folder.appending(path: "run.sh").path
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)

        // Act
        try ConflictFileContents.save("#!/bin/sh\necho\n", to: "run.sh", in: repository.folder)

        // Assert
        let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(permissions == 0o755)
        #expect(try repository.contents(of: "run.sh") == "#!/bin/sh\necho\n")
    }
}
