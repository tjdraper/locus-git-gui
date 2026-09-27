import Foundation
import Testing

struct HistoryWindowTitleTests {
    private let contents = SidebarContents(
        refs: ["refs/heads/feature/login", "refs/remotes/team/a/main", "refs/tags/v1.0"].map { Ref(name: $0, commit: "abc") },
        remoteNames: ["team/a"],
        stashes: [Stash(commit: "def", date: Date(timeIntervalSince1970: 0), message: "On main: wip")]
    )

    @Test
    func eachKindIsNamedAsTheSidebarNamesIt() {
        // Act
        let branch = HistoryWindowTitle(.ref("refs/heads/feature/login"), in: contents)
        let remoteBranch = HistoryWindowTitle(.ref("refs/remotes/team/a/main"), in: contents)
        let tag = HistoryWindowTitle(.ref("refs/tags/v1.0"), in: contents)
        let remote = HistoryWindowTitle(.remote("team/a"), in: contents)
        let stash = HistoryWindowTitle(.stash("def"), in: contents)

        // Assert
        #expect([branch.name, branch.kind] == ["feature/login", "Branch"])
        #expect([remoteBranch.name, remoteBranch.kind] == ["team/a/main", "Remote Branch"])
        #expect([tag.name, tag.kind] == ["v1.0", "Tag"])
        #expect([remote.name, remote.kind] == ["team/a", "Remote"])
        #expect([stash.name, stash.kind] == ["On main: wip", "Stash"])
    }

    @Test
    func somethingTheRepositoryNoLongerHasIsNamedFromItself() {
        // Act
        let branch = HistoryWindowTitle(.ref("refs/heads/gone"), in: contents)
        let stash = HistoryWindowTitle(.stash("1234567890"), in: nil)

        // Assert
        #expect(branch.name == "gone")
        #expect(stash.name == "Stash 1234567")
        #expect(stash.gone == "Dropped")
    }
}
