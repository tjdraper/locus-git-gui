import Foundation
import Testing

struct RepositoryViewStateListTests {
    private let suiteName = "RepositoryViewStateListTests-\(UUID().uuidString)"

    private func makeDefaults() throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func state(selecting branch: String) -> RepositoryViewState {
        var state = RepositoryViewState()
        state.selection = .ref("refs/heads/\(branch)")
        return state
    }

    @Test
    func aRepositoryNeverSeenHasTheDefaultState() {
        // Arrange
        let list = RepositoryViewStateList()

        // Act
        let state = list.state(for: "/work/website")

        // Assert
        #expect(state == RepositoryViewState())
        #expect(state.columns == nil)
    }

    @Test
    func eachRepositoryKeepsItsOwnState() {
        // Arrange
        var list = RepositoryViewStateList()

        // Act
        list.set(state(selecting: "main"), for: "/work/website")
        list.set(state(selecting: "develop"), for: "/work/api")

        // Assert
        #expect(list.state(for: "/work/website") == state(selecting: "main"))
        #expect(list.state(for: "/work/api") == state(selecting: "develop"))
        #expect(list.entries.map(\.repository) == ["/work/api", "/work/website"])
    }

    @Test
    func theLeastRecentlyChangedAreForgottenPastTheLimit() {
        // Arrange
        var list = RepositoryViewStateList()
        for index in 0 ..< RepositoryViewStateList.maxEntries {
            list.set(state(selecting: "main"), for: "/work/\(index)")
        }

        // Act
        list.set(state(selecting: "main"), for: "/work/0")
        list.set(state(selecting: "main"), for: "/work/new")

        // Assert
        #expect(list.entries.count == RepositoryViewStateList.maxEntries)
        #expect(list.entries.first?.repository == "/work/new")
        #expect(list.entries.contains { $0.repository == "/work/0" })
        #expect(!list.entries.contains { $0.repository == "/work/1" })
    }

    @Test
    func savedStateReadsBack() throws {
        // Arrange
        let defaults = try makeDefaults()
        var state = RepositoryViewState()
        state.selection = .stash("abc")
        state.collapsedSections = [.tags]
        state.collapsedRemotes = ["origin"]
        state.columns = .init(sidebarWidth: 240, historyWidth: 420, isSidebarCollapsed: true)
        state.windowFrame = "100 200 1200 760 0 0 1512 949 "
        var list = RepositoryViewStateList()
        list.set(state, for: "/work/website")

        // Act
        list.save(to: defaults)
        let read = RepositoryViewStateList(defaults: defaults)

        // Assert
        #expect(read == list)
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
    }
}
