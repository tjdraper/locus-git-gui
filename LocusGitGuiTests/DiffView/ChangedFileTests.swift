import Foundation
import Testing

struct ChangedFileTests {
    private let blob = String(repeating: "a", count: 40)
    private let zero = String(repeating: "0", count: 40)

    @Test
    func readsEachStatusPathModeAndObject() throws {
        // Arrange
        let output = Data((
            ":100644 100644 \(blob) \(blob) M\0a.txt\0"
                + ":000000 100644 \(zero) \(blob) A\0dir/b c.txt\0"
                + ":100644 100644 \(blob) \(blob) R086\0old.txt\0new.txt\0"
                + ":100644 000000 \(blob) \(zero) D\0gone.txt\0"
        ).utf8)

        // Act
        let files = try ChangedFile.parseRaw(output)

        // Assert
        #expect(files.map(\.path) == ["a.txt", "dir/b c.txt", "new.txt", "gone.txt"])
        #expect(files.map(\.change) == [.modified, .added, .renamed, .deleted])
        #expect(files.map(\.originalPath) == [nil, nil, "old.txt", nil])
        #expect(files[1].oldObject == nil)
        #expect(files[1].newObject == blob)
        #expect(files[3].newMode == ChangedFile.absentMode)
    }

    @Test
    func noOutputIsNoFiles() throws {
        // Act
        let files = try ChangedFile.parseRaw(Data())

        // Assert
        #expect(files.isEmpty)
    }

    @Test
    func aRenameMissingItsNewPathIsUnreadable() {
        // Arrange
        let output = Data(":100644 100644 \(blob) \(blob) R100\0old.txt\0".utf8)

        // Act & Assert
        #expect(throws: UnreadableGitOutput.self) {
            try ChangedFile.parseRaw(output)
        }
    }

    @Test
    func aModeChangeIsWordedForPeople() {
        // Arrange
        let madeExecutable = ChangedFile(change: .modified, path: "run.sh", originalPath: nil, oldMode: "100644", newMode: "100755")
        let added = ChangedFile(change: .added, path: "run.sh", originalPath: nil, newMode: "100755")

        // Assert
        #expect(madeExecutable.modeChange == "Made executable")
        #expect(added.modeChange == nil)
    }

    @Test
    func anImageIsRecognizedByItsExtensionUnlessItIsALink() {
        // Arrange
        let image = ChangedFile(change: .modified, path: "Icons/App.PNG", originalPath: nil, oldMode: "100644", newMode: "100644")
        let link = ChangedFile(change: .modified, path: "icon.png", originalPath: nil, oldMode: "120000", newMode: "120000")

        // Assert
        #expect(image.isImage)
        #expect(!link.isImage)
    }
}
