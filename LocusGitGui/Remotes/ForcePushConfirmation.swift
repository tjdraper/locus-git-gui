import AppKit

/// Asks before a force push, saying what the remote's branch loses and naming the commit it's at,
/// which this repository keeps and which can be pushed back to undo it.
enum ForcePushConfirmation {
    /// Where the upstream is as of the last fetch.
    struct Replaced {
        let hash: String
        let subject: String
        /// On the upstream but not the branch, so no longer on the remote once it's replaced.
        let commitsOnlyThere: Int

        var shortHash: String {
            String(hash.prefix(7))
        }
    }

    static let upstreamCommand = GitCommand.reading(["log", "-1", "--format=%H%x00%s", "@{upstream}"])

    static func readReplaced(running run: (GitCommand) async throws -> ChildProcess.Result) async -> Replaced? {
        guard let commit = try? await run(upstreamCommand), commit.status == 0,
              let fields = String(bytes: commit.standardOutput, encoding: .utf8)?
                  .trimmingCharacters(in: .newlines)
                  .split(separator: "\0", omittingEmptySubsequences: false),
              fields.count == 2,
              let count = try? await run(RemoteCommand.upstreamOnlyCount), count.status == 0,
              let commitsOnlyThere = String(bytes: count.standardOutput, encoding: .utf8)
                  .flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
        else { return nil }
        return Replaced(hash: String(fields[0]), subject: String(fields[1]), commitsOnlyThere: commitsOnlyThere)
    }

    /// Return force pushes and Escape cancels. The button isn't marked destructive, since macOS then
    /// keeps Return off it.
    static func ask(branch: String, upstream: String, replaced: Replaced?, on window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Force push “\(branch)” to “\(upstream)”?"
        alert.informativeText = [
            lost(branch: branch, upstream: upstream, replaced: replaced),
            "If the remote’s branch has changed since the last fetch, the push stops instead.",
        ].joined(separator: " ")
        alert.addButton(withTitle: "Force Push")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return await AlertPresentation.run(alert, on: window) == .alertFirstButtonReturn
    }

    private static func lost(branch: String, upstream: String, replaced: Replaced?) -> String {
        guard let replaced else {
            return "The remote’s branch is replaced with “\(branch)”, and commits only it has are no longer on the remote."
        }
        let kept = "“\(upstream)” is at \(replaced.shortHash) (“\(replaced.subject)”), which this repository keeps, "
            + "so it can be pushed back."
        switch replaced.commitsOnlyThere {
        case 0:
            return "Every commit on “\(upstream)” is also on “\(branch)”, so an ordinary push would do. \(kept)"
        case 1:
            return "“\(upstream)” has 1 commit that “\(branch)” doesn’t, which will no longer be on the remote. \(kept)"
        default:
            return "“\(upstream)” has \(replaced.commitsOnlyThere) commits that “\(branch)” doesn’t, "
                + "which will no longer be on the remote. \(kept)"
        }
    }
}
