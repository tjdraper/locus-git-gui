import Testing

struct OperationContextTests {
    private func context(_ names: [String]) -> OperationContext {
        let refs = names.map { Ref(name: $0, commit: "a") }
        return OperationContext(refs: refs, contents: SidebarContents(refs: refs, remoteNames: ["origin"], stashes: []))
    }

    @Test
    func givesGitTheShortNameWhenOnlyOneRefHasIt() throws {
        // Arrange
        let context = context(["refs/heads/feature", "refs/remotes/origin/main"])

        // Act
        let branch = try #require(context.revision(.ref("refs/heads/feature")))
        let remote = try #require(context.revision(.ref("refs/remotes/origin/main")))

        // Assert
        #expect(branch.argument == "feature")
        #expect(remote.argument == "origin/main")
    }

    @Test
    func givesGitTheFullNameWhenAnotherRefSharesTheShortOne() throws {
        // Arrange
        let context = context(["refs/heads/feature", "refs/tags/feature", "refs/heads/origin/main", "refs/remotes/origin/main"])

        // Act
        let branch = try #require(context.revision(.ref("refs/heads/feature")))
        let remote = try #require(context.revision(.ref("refs/remotes/origin/main")))

        // Assert
        #expect(branch.argument == "refs/heads/feature")
        #expect(branch.name == "feature")
        #expect(remote.argument == "refs/remotes/origin/main")
    }

    @Test
    func givesGitTheFullNameOfATagThatLooksLikeAnOption() throws {
        // Arrange
        let context = context(["refs/tags/--exec=touch${IFS}x"])

        // Act
        let tag = try #require(context.revision(.ref("refs/tags/--exec=touch${IFS}x")))

        // Assert
        #expect(tag.argument == "refs/tags/--exec=touch${IFS}x")
    }
}
