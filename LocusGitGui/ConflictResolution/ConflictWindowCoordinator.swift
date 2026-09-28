import AppKit

/// A repository's conflict window: there's one at most, opening it again brings it forward, and it
/// closes with the repository's window. It's told of every refresh, which lists the conflicted files
/// and says what's being merged, for naming each side.
final class ConflictWindowCoordinator {
    var showFailure: ((GitFailure, NSWindow, _ retry: @escaping () -> Void) -> Void)?
    /// When the window opens, closes, moves or shows another file.
    var onChange: (() -> Void)?
    private let commands: RepositoryCommandRunner
    private let queue: WorkingAreaCommandQueue
    private let operationStatus: OperationStatus
    private var controller: ConflictWindowController?
    private var conflicted: [(path: String, conflict: RepositoryStatus.Conflict)] = []
    private var operation: InProgressOperation?
    private var checkedOutBranch: String?
    private var rebaseOnto: String?
    private var theirsCommit: String?
    private var refs: [Ref] = []
    private weak var repositoryWindow: RepositoryWindowController?

    init(
        commands: RepositoryCommandRunner,
        queue: WorkingAreaCommandQueue,
        operationStatus: OperationStatus,
        repositoryWindow: RepositoryWindowController
    ) {
        self.commands = commands
        self.queue = queue
        self.operationStatus = operationStatus
        self.repositoryWindow = repositoryWindow
    }

    var window: NSWindow? {
        controller?.window
    }

    var hasConflicts: Bool {
        !conflicted.isEmpty
    }

    /// Showing `file` when it has a conflict, as it was left when `record` says, and otherwise
    /// cascaded from the window it was opened from.
    @discardableResult
    func show(
        file: String? = nil,
        from sourceWindow: NSWindow?,
        repositoryName: String,
        record: OpenWindows.ConflictWindow? = nil
    ) -> NSWindow? {
        if let controller {
            if let file {
                controller.select(file: file)
            }
            controller.showWindow(nil)
            return controller.window
        }
        let controller = ConflictWindowController(
            commands: commands,
            queue: queue,
            operationStatus: operationStatus,
            repositoryName: repositoryName
        )
        controller.repositoryWindow = repositoryWindow
        controller.sideNames = { [weak self] label in self?.names(theirsLabel: label) ?? ConflictSideNames(ours: "HEAD", theirs: "Theirs") }
        controller.showFailure = { [weak self, weak controller] failure, retry in
            guard let window = controller?.window else { return }
            self?.showFailure?(failure, window, retry)
        }
        controller.onClose = { [weak self] in
            self?.controller = nil
            self?.onChange?()
        }
        self.controller = controller
        controller.show(conflicted)
        if let record {
            controller.restore(record)
        }
        if let file {
            controller.select(file: file)
        }
        if let window = controller.window {
            OpenedWindowPlacement.place(window, at: record?.frame, cascadingFrom: sourceWindow)
        }
        controller.showWindow(nil)
        controller.onChange = { [weak self] in self?.onChange?() }
        onChange?()
        return controller.window
    }

    var record: OpenWindows.ConflictWindow? {
        controller?.record
    }

    func showRepositoryName(_ name: String) {
        controller?.window?.subtitle = name
    }

    /// After every refresh.
    func show(_ snapshot: RepositorySnapshot) {
        conflicted = snapshot.status.files.compactMap { file in
            if case let .conflicted(conflict) = file.state { (file.path, conflict) } else { nil }
        }
        operation = snapshot.operation
        checkedOutBranch = snapshot.status.branch.name
        let gitDirectory = commands.repository.gitDirectory
        rebaseOnto = ConflictSideNames.readRebaseOnto(gitDirectory: gitDirectory)
        theirsCommit = ConflictSideNames.readTheirsCommit(gitDirectory: gitDirectory)
        controller?.show(conflicted)
    }

    /// After every refresh, once the repository's refs have been read, to name the branch a rebase
    /// is going onto.
    func show(refs: [Ref]) {
        self.refs = refs
        controller?.list.names = names(theirsLabel: nil)
    }

    private func names(theirsLabel: String?) -> ConflictSideNames {
        ConflictSideNames(
            operation: operation,
            checkedOutBranch: checkedOutBranch,
            rebaseOnto: rebaseOnto.map { ConflictSideNames.name(of: $0, in: refs) },
            theirsLabel: theirsLabel,
            theirsCommit: theirsCommit.map { ConflictSideNames.name(of: $0, in: refs) }
        )
    }

    func close() {
        controller?.close()
        controller = nil
    }
}
