import Foundation
import Testing

/// Pushes and pulls run against a bare repository in a scratch folder. What needs a server, such as
/// a refused password or an unreachable host, is Git's and SSH's output captured from real runs.
struct RecognizedRemoteFailureTests {
    /// A bare remote with one commit on `main`, and two clones of it.
    private struct Remote {
        let bare: FixtureRepository
        let first: FixtureRepository
        let second: FixtureRepository

        static func make() async throws -> Remote {
            let bare = try FixtureRepository(folder: TestGit.makeScratchFolder())
            try await bare.git("init", "--quiet", "--bare", "--initial-branch=main")
            let first = try await bare.clone()
            try await first.git("checkout", "--quiet", "-b", "main")
            try await first.commit("First", writing: "a", to: "a.txt")
            try await first.git("push", "--quiet", "--set-upstream", "origin", "main")
            let second = try await bare.clone()
            return Remote(bare: bare, first: first, second: second)
        }

        /// Moves the remote's `main` on from the second clone, so the first is behind it.
        func advanceFromSecondClone() async throws {
            try await second.commit("From the second clone", writing: "b", to: "b.txt")
            try await second.git("push", "--quiet")
        }

        func remove() {
            [bare, first, second].forEach { $0.remove() }
        }
    }

    @Test
    func pushingBehindTheRemoteIsRecognized() async throws {
        // Arrange
        let remote = try await Remote.make()
        defer { remote.remove() }
        try await remote.advanceFromSecondClone()
        try await remote.first.commit("From the first clone", writing: "c", to: "c.txt")

        // Act
        let result = try await remote.first.run(.changing(["push", "--progress"]))

        // Assert
        #expect(RecognizedGitFailure.recognize(result) == .pushBehindRemote)
    }

    @Test
    func aForcePushThatFindsTheRemoteMovedIsRecognized() async throws {
        // Arrange
        let remote = try await Remote.make()
        defer { remote.remove() }
        try await remote.first.commit("From the first clone", writing: "c", to: "c.txt")
        try await remote.first.git("fetch", "--quiet")
        try await remote.advanceFromSecondClone()

        // Act
        let result = try await remote.first.run(.changing(["push", "--progress", "--force-with-lease"]))

        // Assert
        #expect(RecognizedGitFailure.recognize(result) == .pushLeaseStale)
    }

    @Test
    func aPushTheServerRefusesKeepsWhatTheServerSaid() async throws {
        // Arrange
        let remote = try await Remote.make()
        defer { remote.remove() }
        try remote.bare.write("#!/bin/sh\necho 'Pushes to main need a pull request.' >&2\nexit 1\n", to: "hooks/pre-receive")
        let hook = remote.bare.folder.appending(path: "hooks/pre-receive")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try await remote.first.commit("Second", writing: "b", to: "b.txt")

        // Act
        let result = try await remote.first.run(.changing(["push", "--progress"]))

        // Assert
        #expect(RecognizedGitFailure.recognize(result) == .pushRefusedByRemote(
            reason: "pre-receive hook declined",
            messages: ["Pushes to main need a pull request."]
        ))
    }

    @Test
    func pullingADivergedBranchWithNoStrategyIsRecognized() async throws {
        // Arrange
        let remote = try await Remote.make()
        defer { remote.remove() }
        try await remote.advanceFromSecondClone()
        try await remote.first.commit("From the first clone", writing: "c", to: "c.txt")

        // Act
        let result = try await remote.first.run(.changing(["pull", "--progress"]))

        // Assert
        #expect(RecognizedGitFailure.recognize(result) == .pullNeedsStrategy)
    }

    @Test
    func pullingAnUpstreamDeletedFromTheRemoteIsRecognized() async throws {
        // Arrange
        let remote = try await Remote.make()
        defer { remote.remove() }
        try await remote.first.git("checkout", "--quiet", "-b", "feature")
        try await remote.first.git("push", "--quiet", "--set-upstream", "origin", "feature")
        try await remote.bare.git("branch", "--quiet", "-D", "feature")

        // Act
        let result = try await remote.first.run(.changing(["pull", "--progress"]))

        // Assert
        #expect(RecognizedGitFailure.recognize(result) == .upstreamGone(branch: "feature"))
    }

    @Test
    func aServerThatIsNotListeningIsUnreachable() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }

        // Act
        let result = try await repository.run(.reading(["ls-remote", "https://127.0.0.1:9/repository.git"]))

        // Assert
        #expect(RecognizedGitFailure.recognize(result) == .unreachable(host: "127.0.0.1"))
    }

    @Test
    func aHostSSHCannotFindIsUnreachable() {
        // Arrange
        let result = Self.failure("""
        ssh: Could not resolve hostname nonexistent.invalid: nodename nor servname provided, or not known
        fatal: Could not read from remote repository.

        Please make sure you have the correct access rights
        and the repository exists.
        """)

        // Act
        let recognized = RecognizedGitFailure.recognize(result)

        // Assert
        #expect(recognized == .unreachable(host: "nonexistent.invalid"))
    }

    @Test
    func aHostHTTPSCannotFindIsUnreachable() {
        // Arrange
        let result = Self.failure(
            "fatal: unable to access 'https://nonexistent.invalid/foo.git/': Could not resolve host: nonexistent.invalid"
        )

        // Act
        let recognized = RecognizedGitFailure.recognize(result)

        // Assert
        #expect(recognized == .unreachable(host: "nonexistent.invalid"))
    }

    @Test
    func aRefusedSSHConnectionIsUnreachable() {
        // Arrange
        let result = Self.failure("""
        ssh: connect to host 127.0.0.1 port 2299: Connection refused
        fatal: Could not read from remote repository.
        """)

        // Act
        let recognized = RecognizedGitFailure.recognize(result)

        // Assert
        #expect(recognized == .unreachable(host: "127.0.0.1"))
    }

    @Test
    func aRefusedSSHKeyIsAnAuthenticationFailure() {
        // Arrange
        let result = Self.failure("""
        git@github.com: Permission denied (publickey).
        fatal: Could not read from remote repository.

        Please make sure you have the correct access rights
        and the repository exists.
        """)

        // Act
        let recognized = RecognizedGitFailure.recognize(result)

        // Assert
        #expect(recognized == .authenticationFailed(.sshKey, server: "git@github.com"))
    }

    @Test
    func aRefusedTokenIsAnAuthenticationFailure() {
        // Arrange
        let result = Self.failure("""
        remote: Invalid username or token. Password authentication is not supported for Git operations.
        fatal: Authentication failed for 'https://github.com/owner/repository.git/'
        """)

        // Act
        let recognized = RecognizedGitFailure.recognize(result)

        // Assert
        #expect(recognized == .authenticationFailed(.https, server: "github.com"))
    }

    @Test
    func aUsernameGitCouldNotAskForIsAnAuthenticationFailure() {
        // Arrange
        let result = Self.failure("fatal: could not read Username for 'https://github.com': terminal prompts disabled")

        // Act
        let recognized = RecognizedGitFailure.recognize(result)

        // Assert
        #expect(recognized == .authenticationFailed(.https, server: "github.com"))
    }

    @Test
    func aChangedHostKeyIsRecognizedBeforeTheFailedVerification() {
        // Arrange
        let result = Self.failure("""
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
        Someone could be eavesdropping on you right now (man-in-the-middle attack)!
        It is also possible that a host key has just been changed.
        The fingerprint for the ED25519 key sent by the remote host is
        SHA256:Zw+4ujWreGrxsQCcz6pmHYN8EGlSq2oTcfSax0g6SSY.
        Please contact your system administrator.
        Offending ED25519 key in /Users/someone/.ssh/known_hosts:1
        Host key for [127.0.0.1]:2222 has changed and you have requested strict checking.
        Host key verification failed.
        fatal: Could not read from remote repository.
        """)

        // Act
        let recognized = RecognizedGitFailure.recognize(result)

        // Assert
        #expect(recognized == .hostKeyChanged(host: "[127.0.0.1]:2222"))
    }

    private static func failure(_ standardError: String) -> ChildProcess.Result {
        ChildProcess.Result(status: 128, standardOutput: Data(), standardError: Data(standardError.utf8))
    }
}
