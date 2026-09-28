import AppKit

/// Saving the result to the file, marking a file resolved, and resolving one by taking a whole
/// version. Git's commands wait their turn in the working area's queue, as staging does, and each
/// failure is shown there with Git's words.
final class ConflictResolutionWorkflow {
    /// Where a confirmation or a failure to save shows.
    var window: () -> NSWindow? = { nil }
    private let commands: RepositoryCommandRunner
    private let queue: WorkingAreaCommandQueue

    init(commands: RepositoryCommandRunner, queue: WorkingAreaCommandQueue) {
        self.commands = commands
        self.queue = queue
    }

    /// Whether it was saved. A failure, such as a file made read-only, is shown, and the edits stay
    /// in the window.
    func save(_ text: String, to path: String) -> Bool {
        do {
            try ConflictFileContents.save(text, to: path, in: commands.repository.workTree)
            queue.noteChange()
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "“\((path as NSString).lastPathComponent)” couldn’t be saved."
            Task { [window] in _ = await AlertPresentation.run(alert, on: window()) }
            return false
        }
    }

    /// Asks first when conflicts are left in the file, since their markers would be committed.
    func markResolved(_ path: String, conflictsLeft: Int) {
        let name = (path as NSString).lastPathComponent
        Task { [weak self] in
            if conflictsLeft > 0 {
                let conflicts = conflictsLeft == 1 ? "1 conflict" : "\(conflictsLeft.formatted()) conflicts"
                let isConfirmed = await Confirmation.ask(
                    "“\(name)” still has \(conflicts). Mark it as resolved anyway?",
                    informativeText: "Git’s conflict markers stay in the file, and are committed with it.",
                    confirmTitle: "Mark as Resolved",
                    on: self?.window()
                )
                guard isConfirmed else { return }
            }
            guard let self else { return }
            queue.run("Git couldn’t mark “\(name)” as resolved.") { [commands] in
                try await WorkingAreaStaging.stage([path], running: commands.run)
            }
        }
    }

    func choose(_ choice: ConflictVersionChoice, for path: String, stages: ConflictStages) {
        let name = (path as NSString).lastPathComponent
        let steps = choice.commands(for: path, stages: stages)
        queue.run("Git couldn’t resolve “\(name)”.") { [commands] in
            for command in steps {
                let result = try await commands.run(command)
                guard result.status == 0 else {
                    throw WorkingAreaStaging.Failure(command: command, result: result)
                }
            }
        }
    }
}
