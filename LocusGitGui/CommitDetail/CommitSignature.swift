import Foundation

/// Whether a commit is signed, and whether its signature checks out on this Mac.
nonisolated struct CommitSignature: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case good
        /// A good signature from a key this Mac doesn't trust.
        case untrusted
        /// Signed, but this Mac lacks what it needs to check it, such as the signer's public key
        /// or, for SSH, an allowed signers file.
        case uncheckable
        case expiredSignature
        case expiredKey
        case revokedKey
        /// The signature doesn't match the commit.
        case bad
        case unsigned
    }

    let status: Status
    /// As GPG or the allowed signers file names them. Nil when unknown.
    let signer: String?
    /// What GPG or `ssh-keygen` said, or why Git couldn't ask them.
    let report: String?

    static let unsigned = CommitSignature(status: .unsigned, signer: nil, report: nil)

    static func rawCommand(_ hash: String) -> GitCommand {
        .reading(["cat-file", "commit", hash])
    }

    static func verifyCommand(_ hash: String) -> GitCommand {
        .reading(["log", "--max-count=1", "--no-show-signature", "--format=%G?%x00%GS%x00%GG", "--end-of-options", hash, "--"])
    }

    /// Checked in the commit itself first, since Git reports an SSH signature it can't check as no
    /// signature at all. That also spares every unsigned commit a run of GPG.
    static func read(_ hash: String, running run: (GitCommand) async throws -> ChildProcess.Result) async throws -> CommitSignature {
        let raw = try await GitReadFailure.read("commit", with: rawCommand(hash), running: run) { $0 }
        guard isSigned(raw) else { return .unsigned }
        let command = verifyCommand(hash)
        let result = try await run(command)
        guard result.status == 0 else {
            throw GitReadFailure(subject: "signature", command: command, result: result, outputWasUnreadable: false)
        }
        do {
            return try parse(result.standardOutput, errors: result.standardError)
        } catch {
            throw GitReadFailure(subject: "signature", command: command, result: result, outputWasUnreadable: true)
        }
    }

    /// A signed commit has a `gpgsig` header, or `gpgsig-sha256` in a SHA-256 repository, among
    /// the headers before the first blank line.
    static func isSigned(_ rawCommit: Data) -> Bool {
        for line in rawCommit.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
            if line.isEmpty {
                return false
            }
            if line.starts(with: Data("gpgsig".utf8)) {
                return true
            }
        }
        return false
    }

    /// The status letter, the signer and the checker's own report, separated by NULs.
    static func parse(_ output: Data, errors: Data) throws -> CommitSignature {
        let fields = output.split(separator: 0, maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3 else {
            throw UnreadableGitOutput(reason: "Signature has \(fields.count) fields, expected 3")
        }
        let signer = try UnreadableGitOutput.text(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        let report = [try UnreadableGitOutput.text(fields[2]), String(bytes: errors, encoding: .utf8) ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return CommitSignature(
            status: status(letter: try UnreadableGitOutput.text(fields[0]).first),
            signer: signer.isEmpty ? nil : signer,
            report: report
        )
    }

    /// Git's `%G?` letters. The commit is known to be signed, so no signature (`N`) means Git
    /// couldn't check it.
    private static func status(letter: Character?) -> Status {
        switch letter {
        case "G": .good
        case "U": .untrusted
        case "X": .expiredSignature
        case "Y": .expiredKey
        case "R": .revokedKey
        case "B": .bad
        default: .uncheckable
        }
    }
}
