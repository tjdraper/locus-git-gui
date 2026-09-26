import Foundation
import Testing

struct CommitSignatureTests {
    /// A repository with one commit signed by a fresh SSH key, and the key's allowed signers line.
    private struct SignedRepository {
        let repository: FixtureRepository
        let keyFolder: URL
        let allowedSigner: String

        func remove() {
            repository.remove()
            try? FileManager.default.removeItem(at: keyFolder)
        }
    }

    private func makeSignedRepository() async throws -> SignedRepository {
        let keyFolder = try TestGit.makeScratchFolder()
        let key = keyFolder.appending(path: "key")
        let keygen = try await ChildProcess(
            executableURL: URL(filePath: "/usr/bin/ssh-keygen"),
            arguments: ["-q", "-t", "ed25519", "-N", "", "-C", "test", "-f", key.path],
            environment: ProcessInfo.processInfo.environment,
            currentDirectoryURL: nil
        ).run()
        #expect(keygen.status == 0)
        let publicKey = try String(contentsOf: keyFolder.appending(path: "key.pub"), encoding: .utf8)
        let repository = try await FixtureRepository.make()
        try await repository.git(
            "-c", "gpg.format=ssh", "-c", "user.signingKey=\(key.path)",
            "commit", "--quiet", "--allow-empty", "-S", "--message", "Signed"
        )
        return SignedRepository(repository: repository, keyFolder: keyFolder, allowedSigner: "signer@example.com \(publicKey)")
    }

    private func signature(of repository: FixtureRepository, _ revision: String = "HEAD") async throws -> CommitSignature {
        let hash = try await repository.git("rev-parse", revision)
        return try await CommitSignature.read(hash) { try await repository.run($0) }
    }

    @Test
    func anUnsignedCommitIsUnsigned() async throws {
        // Arrange
        let repository = try await FixtureRepository.make()
        defer { repository.remove() }
        try await repository.commit("Plain", writing: "a", to: "a.txt")

        // Act
        let signature = try await signature(of: repository)

        // Assert
        #expect(signature == .unsigned)
    }

    @Test
    func anSSHSignatureWithoutAnAllowedSignersFileCantBeChecked() async throws {
        // Arrange
        let signed = try await makeSignedRepository()
        defer { signed.remove() }

        // Act
        let signature = try await signature(of: signed.repository)

        // Assert
        #expect(signature.status == .uncheckable)
        #expect(signature.report?.contains("allowedSignersFile") == true)
    }

    @Test
    func aSignatureFromAnAllowedSignerIsGood() async throws {
        // Arrange
        let signed = try await makeSignedRepository()
        defer { signed.remove() }
        let allowedSigners = signed.keyFolder.appending(path: "allowed_signers")
        try signed.allowedSigner.write(to: allowedSigners, atomically: true, encoding: .utf8)
        try await signed.repository.git("config", "gpg.ssh.allowedSignersFile", allowedSigners.path)

        // Act
        let signature = try await signature(of: signed.repository)

        // Assert
        #expect(signature.status == .good)
        #expect(signature.signer == "signer@example.com")
    }

    @Test
    func aSignatureThatNoLongerMatchesItsCommitIsBad() async throws {
        // Arrange
        let signed = try await makeSignedRepository()
        defer { signed.remove() }
        let allowedSigners = signed.keyFolder.appending(path: "allowed_signers")
        try signed.allowedSigner.write(to: allowedSigners, atomically: true, encoding: .utf8)
        try await signed.repository.git("config", "gpg.ssh.allowedSignersFile", allowedSigners.path)
        let raw = try await signed.repository.git("cat-file", "commit", "HEAD")
        let altered = signed.keyFolder.appending(path: "altered")
        try (raw.replacingOccurrences(of: "\n\nSigned", with: "\n\nAltered") + "\n").write(to: altered, atomically: true, encoding: .utf8)
        let forged = try await signed.repository.git("hash-object", "-t", "commit", "-w", altered.path)

        // Act
        let signature = try await signature(of: signed.repository, forged)

        // Assert
        #expect(signature.status == .bad)
    }

    @Test
    func onlyASignatureHeaderBeforeTheMessageCounts() {
        // Arrange
        let inMessage = Data("tree abc\nauthor A\n\ngpgsig in the message\n".utf8)
        let inHeader = Data("tree abc\ngpgsig -----BEGIN SSH SIGNATURE-----\n more\n\nSubject\n".utf8)

        // Act & Assert
        #expect(!CommitSignature.isSigned(inMessage))
        #expect(CommitSignature.isSigned(inHeader))
    }
}
