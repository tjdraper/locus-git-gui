import AppKit
import os

/// Makes a commit from what's staged, or amends the last one, with the message being written. A
/// commit that fails, such as when a hook stops it, keeps the message for the next try.
final class CommitWorkflow {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "WorkingArea")

    /// The commit an amend would rewrite, as of the last refresh. Nil before the first commit.
    var head: String?
    private let commands: RepositoryCommandRunner
    private let editor: CommitMessageEditor
    private let queue: WorkingAreaCommandQueue
    /// The merge whose message has been offered, so a message cleared on purpose stays cleared.
    private var offeredMergeMessage: String?

    init(commands: RepositoryCommandRunner, editor: CommitMessageEditor, queue: WorkingAreaCommandQueue) {
        self.commands = commands
        self.editor = editor
        self.queue = queue
        editor.commit = { [weak self] in self?.commit() }
        editor.toggleAmend = { [weak self] in self?.toggleAmend() }
    }

    /// Waits for staging queued before it, so a commit made straight after staging includes it.
    /// Typing on while it runs, such as while a slow hook works, starts the next message, which the
    /// commit leaves alone.
    func commit() {
        guard editor.canCommit else {
            NSSound.beep()
            return
        }
        let message = editor.message
        let amend = editor.isAmending
        editor.isCommitting = true
        queue.run(amend ? "Git couldn’t amend the last commit." : "Git couldn’t make the commit.") { [weak self, commands] in
            defer { self?.editor.isCommitting = false }
            try await WorkingAreaStaging.commit(message.text, amend: amend, running: commands.run)
            guard let self else { return }
            if editor.message == message {
                editor.finishCommitting()
            } else if amend {
                editor.finishAmendingKeepingMessage()
            }
        }
    }

    /// Loads the last commit's message to edit, or puts back what was being written before.
    func toggleAmend() {
        if editor.isAmending {
            editor.stopAmending()
            return
        }
        guard let head, !editor.isLoadingAmend else { return }
        editor.isLoadingAmend = true
        Task { [weak self, commands] in
            defer { self?.editor.isLoadingAmend = false }
            do {
                let text = try await GitReadFailure.read("commit message", with: CommitDetail.messageCommand(head), running: commands.run) {
                    try UnreadableGitOutput.text($0)
                }
                let message = CommitMessage(parsing: text)
                self?.editor.beginAmending(CommitMessageEditor.AmendedCommit(hash: head, subject: message.subject), message: message)
            } catch {
                NSSound.beep()
                Self.log.error("Reading the last commit's message failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    /// Git writes the message a merge will have, which a merge stopped on conflicts leaves for the
    /// commit that finishes it. Offered once per merge, and only in place of an empty message.
    func offerMergeMessage(in gitDirectory: URL) {
        let url = gitDirectory.appending(path: "MERGE_MSG")
        guard editor.message.isEmpty, !editor.isAmending,
              let text = try? String(contentsOf: url, encoding: .utf8), text != offeredMergeMessage else { return }
        offeredMergeMessage = text
        Task { [weak self, commands] in
            let comment = await Self.commentCharacter(for: text, running: commands.run)
            guard let self, editor.message.isEmpty, !editor.isAmending else { return }
            // Git's comments, such as the list of conflicts, which `git commit` would take out itself.
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.hasPrefix(comment) }
            editor.replaceMessage(with: CommitMessage(parsing: lines.joined(separator: "\n")))
        }
    }

    /// `core.commentChar`, which some people set to something other than `#`. Set to `auto`, Git
    /// picks one the message doesn't start a line with, which the list of conflicts shows.
    private static func commentCharacter(
        for message: String,
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async -> String {
        let configured = try? await run(.reading(["config", "--get", "core.commentChar"]))
        let value = configured.flatMap { $0.status == 0 ? String(bytes: $0.standardOutput, encoding: .utf8) : nil }?
            .trimmingCharacters(in: .newlines) ?? ""
        if !value.isEmpty, value != "auto" {
            return value
        }
        let conflicts = message.split(separator: "\n").first { $0.count > 1 && $0.dropFirst() == " Conflicts:" }
        return conflicts.map { String($0.prefix(1)) } ?? "#"
    }
}
