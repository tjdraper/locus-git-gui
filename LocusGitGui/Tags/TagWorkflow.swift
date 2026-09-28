import AppKit

/// Makes and deletes tags in this repository. Deleting one asks first and names the commit it was
/// on, where making it again brings it back.
final class TagWorkflow {
    var context: () -> OperationContext = { OperationContext() }
    var repositoryWindow: () -> NSWindow? = { nil }
    var notice: ((OperationStatus.Notice) -> Void)?
    private let runner: OperationRunner

    init(runner: OperationRunner) {
        self.runner = runner
    }

    /// `startTitle` names the commit in the sheet, such as “1a2b3c4 (“Subject”)”.
    func newTag(at commit: String, startTitle: String, from window: NSWindow?) {
        guard ReadOnlyLock.allowsChange(in: window ?? repositoryWindow()) else { return }
        Task { [weak self] in
            guard let self, let window = window ?? repositoryWindow() else { return }
            let result = await FormSheet.ask(on: window) { [context] finish in
                TagForm(message: "On \(startTitle).", takenNames: context().tagNames, finish: finish)
            }
            guard let result else { return }
            runner.perform(from: window) { steps in
                try await steps.run(
                    TagCommand.create(result.name, at: commit, message: result.message),
                    failing: "Git couldn’t make the tag “\(result.name)”."
                )
            }
        }
    }

    func delete(_ tag: String, from window: NSWindow?) {
        guard ReadOnlyLock.allowsChange(in: window ?? repositoryWindow()) else { return }
        Task { [weak self] in
            guard let self else { return }
            let point = await RestorePoint.read("refs/tags/\(tag)", running: runner.commands.run)
            let isConfirmed = await Confirmation.ask(
                "Delete the tag “\(tag)”?",
                informativeText: (point.map { "It’s on \($0.described), where making it again brings it back. " } ?? "")
                    + "Remotes that have it keep their copy.",
                confirmTitle: "Delete",
                on: window ?? repositoryWindow()
            )
            guard isConfirmed else { return }
            runner.perform(from: window) { [weak self] steps in
                try await steps.run(TagCommand.delete(tag), failing: "Git couldn’t delete the tag “\(tag)”.")
                if let point {
                    self?.notice?(OperationStatus.Notice(
                        message: "The tag “\(tag)” was on \(point.described) before it was deleted.",
                        hash: point.hash
                    ))
                }
            }
        }
    }
}
