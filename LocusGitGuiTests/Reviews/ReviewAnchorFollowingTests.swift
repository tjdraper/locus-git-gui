import Foundation
import Testing

struct ReviewAnchorFollowingTests {
    /// Line 5 commented on in a ten-line file, then the file changed as `after` says.
    private func follow(_ lines: ClosedRange<Int>, after: [String]) async throws -> ClosedRange<Int>? {
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        let before = (1 ... 10).map { "line \($0)\n" }.joined()
        try repository.write(before, to: "a.txt")
        let old = try await repository.git("hash-object", "-w", "a.txt")
        try repository.write(after.map { $0 + "\n" }.joined(), to: "a.txt")
        let new = try await repository.git("hash-object", "-w", "a.txt")
        let (result, patches) = try await repository.readPatch(ReviewAnchorFollowing.changesCommand(from: old, to: new), .oneFile)
        #expect(result.status == 0)
        return ReviewAnchorFollowing.follow(lines, through: patches.first?.hunks ?? [])
    }

    private var lines: [String] {
        (1 ... 10).map { "line \($0)" }
    }

    @Test
    func linesAddedAboveMoveTheCommentDown() async throws {
        // Arrange
        let after = ["new a", "new b"] + lines

        // Act
        let followed = try await follow(5 ... 5, after: after)

        // Assert
        #expect(followed == 7 ... 7)
    }

    @Test
    func linesRemovedAboveMoveTheCommentUp() async throws {
        // Arrange
        let after = Array(lines.dropFirst(3))

        // Act
        let followed = try await follow(5 ... 6, after: after)

        // Assert
        #expect(followed == 2 ... 3)
    }

    @Test
    func changesBelowLeaveTheCommentWhereItWas() async throws {
        // Arrange
        var after = lines
        after[8] = "changed"
        after.append("added")

        // Act
        let followed = try await follow(5 ... 5, after: after)

        // Assert
        #expect(followed == 5 ... 5)
    }

    @Test
    func changingTheLineItselfOutdatesTheComment() async throws {
        // Arrange
        var after = lines
        after[4] = "line five"

        // Act
        let followed = try await follow(5 ... 5, after: after)

        // Assert
        #expect(followed == nil)
    }

    @Test
    func addingALineBetweenTheLinesOutdatesTheComment() async throws {
        // Arrange
        var after = lines
        after.insert("between", at: 5)

        // Act
        let followed = try await follow(5 ... 6, after: after)

        // Assert
        #expect(followed == nil)
    }

    @Test
    func addingALineRightAfterTheLinesLeavesThem() async throws {
        // Arrange
        var after = lines
        after.insert("after", at: 6)

        // Act
        let followed = try await follow(5 ... 6, after: after)

        // Assert
        #expect(followed == 5 ... 6)
    }
}
