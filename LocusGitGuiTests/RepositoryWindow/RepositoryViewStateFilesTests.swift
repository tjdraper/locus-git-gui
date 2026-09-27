import Foundation
import Testing

struct RepositoryViewStateFilesTests {
    private func makeFiles() throws -> RepositoryViewStateFiles {
        RepositoryViewStateFiles(folder: FileManager.default.temporaryDirectory.appending(path: "ViewStates-\(UUID().uuidString)"))
    }

    private func remove(_ files: RepositoryViewStateFiles) {
        try? FileManager.default.removeItem(at: files.folder)
    }

    private func state(selecting branch: String) -> RepositoryViewState {
        var state = RepositoryViewState()
        state.selection = .ref("refs/heads/\(branch)")
        return state
    }

    @Test
    func aRepositoryNeverSeenHasNoState() throws {
        // Arrange
        let files = try makeFiles()
        defer { remove(files) }

        // Act
        let state = files.read("/work/website")

        // Assert
        #expect(state == nil)
    }

    @Test
    func eachRepositoryKeepsItsOwnState() throws {
        // Arrange
        let files = try makeFiles()
        defer { remove(files) }

        // Act
        try files.write(state(selecting: "main"), for: "/work/website")
        try files.write(state(selecting: "develop"), for: "/work/api")
        try files.write(state(selecting: "release"), for: "/work/website")

        // Assert
        #expect(files.read("/work/website") == state(selecting: "release"))
        #expect(files.read("/work/api") == state(selecting: "develop"))
    }

    @Test
    func savedStateReadsBack() throws {
        // Arrange
        let files = try makeFiles()
        defer { remove(files) }
        var state = RepositoryViewState()
        state.selection = .stash("abc")
        state.collapsedSections = [.tags]
        state.collapsedRemotes = ["origin"]
        state.columns = .init(sidebarWidth: 240, historyWidth: 420, isSidebarCollapsed: true)
        state.windowFrame = "100 200 1200 760 0 0 1512 949 "
        state.sidebarFilter = "feature"
        state.findText = "login"
        state.findField = .author
        state.workingAreaFilter = .staged
        state.historyPlaces.set(HistoryPlace(selection: .commit("abc"), topCommit: "def"), for: .ref("refs/heads/main"))
        state.diffPlaces.set(DiffPlace(collapsed: [DiffFile.Identity(group: nil, path: "a.txt")]), in: .commit("abc"))
        state.openWindows = OpenWindows(
            commits: [.init(commit: "abc", frame: "10 20 720 760 0 0 1512 949 ")],
            files: [.init(commit: nil, file: DiffFile.Identity(group: 2, path: "b.txt"), frame: nil, scroll: nil)],
            histories: [.init(item: .ref("refs/tags/v1"), frame: nil, place: HistoryPlace(selection: .commit("abc")))],
            workingArea: .init(frame: nil, filter: .unstaged),
            isActivityShown: true
        )

        // Act
        try files.write(state, for: "/work/website")

        // Assert
        #expect(files.read("/work/website") == state)
    }

    @Test
    func stateSavedWithFewerFieldsStillReads() throws {
        // Arrange
        let json = Data(#"{"selection":{"remote":{"_0":"origin"}}}"#.utf8)

        // Act
        let state = try JSONDecoder().decode(RepositoryViewState.self, from: json)

        // Assert
        #expect(state.selection == .remote("origin"))
        #expect(state.collapsedSections.isEmpty)
        #expect(state.collapsedRemotes.isEmpty)
        #expect(state.columns == nil)
        #expect(state.windowFrame == nil)
        #expect(state.sidebarFilter.isEmpty)
        #expect(state.workingAreaFilter == .all)
        #expect(state.openWindows == OpenWindows())
    }

    @Test
    func openWindowsSavedBeforeHistoryWindowsStillRead() throws {
        // Arrange
        let json = Data(#"{"commits":[{"commit":"abc"}],"files":[],"isActivityShown":true}"#.utf8)

        // Act
        let windows = try JSONDecoder().decode(OpenWindows.self, from: json)

        // Assert
        #expect(windows.commits.map(\.commit) == ["abc"])
        #expect(windows.histories.isEmpty)
        #expect(windows.isActivityShown)
    }

    @Test
    func pruningForgetsTheLeastRecentlyWritten() throws {
        // Arrange
        let files = try makeFiles()
        defer { remove(files) }
        for (index, repository) in ["/work/a", "/work/b", "/work/c"].enumerated() {
            try files.write(state(selecting: "main"), for: repository)
            let written = Date(timeIntervalSince1970: Double(index))
            try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: files.url(for: repository).path)
        }

        // Act
        files.prune(keeping: 2)

        // Assert
        #expect(files.read("/work/a") == nil)
        #expect(files.read("/work/b") != nil)
        #expect(files.read("/work/c") != nil)
    }
}
