import Testing

struct RemoteBranchCheckoutTests {
    @Test
    func switchesToTheBranchThatTracksItWhateverItsName() {
        // Arrange
        let refs = [
            Ref(name: "refs/heads/main", commit: "a"),
            Ref(name: "refs/heads/mine", commit: "b", upstream: "refs/remotes/origin/feature"),
        ]

        // Act
        let plan = RemoteBranchCheckout.plan(
            remoteBranch: "refs/remotes/origin/feature",
            remote: "origin",
            nameOnRemote: "feature",
            refs: refs
        )

        // Assert
        #expect(plan == .switchTo(branch: "mine"))
    }

    @Test
    func makesABranchOfTheSameNameWhenNoneTracksIt() {
        // Arrange
        let refs = [Ref(name: "refs/heads/main", commit: "a", upstream: "refs/remotes/origin/main")]

        // Act
        let plan = RemoteBranchCheckout.plan(
            remoteBranch: "refs/remotes/origin/feature",
            remote: "origin",
            nameOnRemote: "feature",
            refs: refs
        )

        // Assert
        #expect(plan == .create(name: "feature"))
    }

    @Test
    func asksForAnotherNameWhenTheNameTracksSomethingElse() {
        // Arrange
        let refs = [
            Ref(name: "refs/heads/feature", commit: "a", upstream: "refs/remotes/upstream/feature"),
            Ref(name: "refs/heads/origin-feature", commit: "b"),
        ]

        // Act
        let plan = RemoteBranchCheckout.plan(
            remoteBranch: "refs/remotes/origin/feature",
            remote: "origin",
            nameOnRemote: "feature",
            refs: refs
        )

        // Assert
        #expect(plan == .askForName(suggested: "origin-feature-2"))
    }
}
