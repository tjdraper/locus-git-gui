import Foundation
import Testing

struct CommitLogStreamTests {
    private func log(of repository: FixtureRepository) async throws -> Data {
        try await repository.run(Commit.logCommand([])).standardOutput
    }

    @Test
    func commitsComeOutOnlyOnceAllTheirFieldsHaveArrived() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("First", writing: "a", to: "a.txt")
        try await repository.commit("Second", writing: "b", to: "b.txt")
        let output = try await log(of: repository)
        var stream = CommitLogStream()

        // Act
        var subjects: [[String]] = []
        for start in stride(from: 0, to: output.count, by: 7) {
            subjects.append(try stream.read(output[start ..< min(start + 7, output.count)]).map(\.subject))
        }

        // Assert
        #expect(subjects.flatMap(\.self) == ["Second", "First"])
        #expect(subjects.filter { !$0.isEmpty }.count == 2)
        #expect(stream.isAtCommitBoundary)
    }

    @Test
    func aCommitCutOffPartwayIsLeftWaiting() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Only", writing: "a", to: "a.txt")
        let output = try await log(of: repository)
        var stream = CommitLogStream()

        // Act
        let commits = try stream.read(output.dropLast())

        // Assert
        #expect(commits.isEmpty)
        #expect(!stream.isAtCommitBoundary)
    }
}
