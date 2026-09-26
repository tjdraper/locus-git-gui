import Foundation
import Testing

struct ChangedFileTests {
    @Test
    func readsEachStatusAndPath() throws {
        // Arrange
        let output = Data("M\0a.txt\0A\0dir/b c.txt\0R086\0old.txt\0new.txt\0D\0gone.txt\0".utf8)

        // Act
        let files = try ChangedFile.parseList(output)

        // Assert
        #expect(files == [
            ChangedFile(change: .modified, path: "a.txt", originalPath: nil),
            ChangedFile(change: .added, path: "dir/b c.txt", originalPath: nil),
            ChangedFile(change: .renamed, path: "new.txt", originalPath: "old.txt"),
            ChangedFile(change: .deleted, path: "gone.txt", originalPath: nil),
        ])
    }

    @Test
    func noOutputIsNoFiles() throws {
        // Act
        let files = try ChangedFile.parseList(Data())

        // Assert
        #expect(files.isEmpty)
    }

    @Test
    func aRenameMissingItsNewPathIsUnreadable() {
        // Arrange
        let output = Data("R100\0old.txt\0".utf8)

        // Act & Assert
        #expect(throws: UnreadableGitOutput.self) {
            try ChangedFile.parseList(output)
        }
    }
}
