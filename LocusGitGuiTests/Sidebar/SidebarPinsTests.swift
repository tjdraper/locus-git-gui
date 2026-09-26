import Foundation
import Testing

struct SidebarPinsTests {
    private func contents(of path: String, in repository: FixtureRepository) -> String? {
        try? String(contentsOf: repository.folder.appending(path: path), encoding: .utf8)
    }

    @Test
    func pinsAreWrittenALineEachAndReadBack() {
        // Arrange
        let pins = SidebarPins([.ref("refs/heads/main"), .stash("abc123"), .ref("refs/tags/v1")])

        // Act
        let read = SidebarPins(parsing: pins.text)

        // Assert
        #expect(pins.text == "refs/heads/main\nstash abc123\nrefs/tags/v1\n")
        #expect(read == pins)
    }

    @Test
    func linesThatArentPinsAreSkipped() {
        // Act
        let pins = SidebarPins(parsing: "refs/heads/main\r\n\n# note\nrefs/heads/main\n  stash abc  \n")

        // Assert
        #expect(pins.items == [.ref("refs/heads/main"), .stash("abc")])
    }

    @Test
    func togglingPinsLastAndUnpins() {
        // Arrange
        var pins = SidebarPins([.ref("refs/heads/main")])

        // Act
        pins.toggle(.ref("refs/tags/v1"))
        pins.toggle(.ref("refs/heads/main"))
        pins.toggle(.remote("origin"))

        // Assert
        #expect(pins.items == [.ref("refs/tags/v1")])
    }

    @Test
    func pinsAreLeftForGitToTrack() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }

        // Act
        try SidebarPins([.ref("refs/heads/main")]).write(to: repository.folder)
        let status = try await repository.git("status", "--porcelain", "--untracked-files=all")

        // Assert
        #expect(status == "?? .locus/.pinned")
        #expect(SidebarPins.read(from: repository.folder).items == [.ref("refs/heads/main")])
    }

    @Test
    func pinsAreSharedWhenTheDisplayNameIsnt() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try RepositoryDisplayName(name: "Marketing Site", isShared: false).write(to: repository.folder)

        // Act
        try SidebarPins([.ref("refs/heads/main")]).write(to: repository.folder)
        let status = try await repository.git("status", "--porcelain", "--untracked-files=all")

        // Assert
        #expect(status == "?? .locus/.pinned")
        #expect(RepositoryDisplayName.read(from: repository.folder) == RepositoryDisplayName(name: "Marketing Site", isShared: false))
    }

    @Test
    func anIgnoreFileWrittenBeforePinsIsUpdatedToShareThem() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try repository.write("Marketing Site\n", to: ".locus/.name")
        try repository.write("*\n", to: ".locus/.gitignore")

        // Act
        try SidebarPins([.ref("refs/heads/main")]).write(to: repository.folder)
        let status = try await repository.git("status", "--porcelain", "--untracked-files=all")

        // Assert
        #expect(status == "?? .locus/.pinned")
        #expect(!RepositoryDisplayName.read(from: repository.folder).isShared)
    }

    @Test
    func unpinningEverythingRemovesTheFileAndAnEmptyFolder() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try SidebarPins([.ref("refs/heads/main")]).write(to: repository.folder)

        // Act
        try SidebarPins().write(to: repository.folder)

        // Assert
        #expect(!FileManager.default.fileExists(atPath: repository.folder.appending(path: ".locus").path))
    }

    @Test
    func aCommittedPinDoesntMakeTheNameTracked() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try SidebarPins([.ref("refs/heads/main")]).write(to: repository.folder)
        try await repository.git("add", "--", ".locus")
        try await repository.git("commit", "--quiet", "--message", "Pin main")

        // Act
        let result = try await repository.run(RepositoryDisplayName.trackedFilesCommand)

        // Assert
        #expect(!RepositoryDisplayName.isTracked(result))
        #expect(contents(of: ".locus/.pinned", in: repository) == "refs/heads/main\n")
    }
}
