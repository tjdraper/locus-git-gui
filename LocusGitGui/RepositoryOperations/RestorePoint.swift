import Foundation

/// The commit a branch, tag or stash was at before a command took it away, named so the user can
/// bring it back, as a destructive command's confirmation and notice do.
nonisolated struct RestorePoint: Equatable, Sendable {
    let hash: String
    let subject: String

    var shortHash: String {
        String(hash.prefix(7))
    }

    /// “1a2b3c4 (“Subject”)”, for the middle of a sentence.
    var described: String {
        "\(shortHash) (“\(subject)”)"
    }

    static func command(_ revision: String) -> GitCommand {
        .reading(["log", "-1", "--no-show-signature", "--format=%H%x00%s", revision, "--"])
    }

    static func parse(_ output: Data) -> RestorePoint? {
        guard let text = String(bytes: output, encoding: .utf8)?.trimmingCharacters(in: .newlines) else { return nil }
        let fields = text.split(separator: "\0", omittingEmptySubsequences: false)
        guard fields.count == 2, !fields[0].isEmpty else { return nil }
        return RestorePoint(hash: String(fields[0]), subject: String(fields[1]))
    }

    static func read(_ revision: String, running run: (GitCommand) async throws -> ChildProcess.Result) async -> RestorePoint? {
        guard let result = try? await run(command(revision)), result.status == 0 else { return nil }
        return parse(result.standardOutput)
    }
}
