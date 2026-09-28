import AppKit
import SwiftUI

/// A repository window's commands for branches, stashes, tags and the history's commits, and the
/// status that shows an operation stopped partway. They take turns with staging and
/// committing in the working area's queue, and each failure shows on the window it was started from.
final class RepositoryOperationsCoordinator {
    /// Shown in the toolbar (`ToolbarStatus`).
    let status = OperationStatus()
    let branches: BranchWorkflow
    let stashes: StashWorkflow
    let tags: TagWorkflow
    let merging: MergeWorkflow
    let commits: CommitOperationWorkflow
    let stopped: StoppedOperationWorkflow
    private(set) lazy var menuCommands = OperationMenuCommands(operations: self)
    /// As of the last refresh.
    private(set) var context = OperationContext()
    /// What the sidebar and the history have selected, which the menu bar's commands act on.
    var sidebarSelection: () -> SidebarItemID? = { nil }
    var selectedCommit: () -> Commit? = { nil }
    /// The history shows the checked-out branch's commits, every one of which is on it.
    var historyShowsCheckedOutBranch: () -> Bool = { false }
    /// For a context menu command that goes on to ask in the palette about the row it was chosen on.
    var selectInSidebar: ((SidebarItemID) -> Void)?
    private(set) var repositoryWindow: () -> NSWindow? = { nil }
    private let runner: OperationRunner
    private let gitDirectory: URL
    private let session: WorkingAreaSession

    init(commands: RepositoryCommandRunner, session: WorkingAreaSession) {
        runner = OperationRunner(commands: commands, queue: session.queue)
        gitDirectory = commands.repository.gitDirectory
        self.session = session
        branches = BranchWorkflow(runner: runner)
        stashes = StashWorkflow(runner: runner)
        tags = TagWorkflow(runner: runner)
        merging = MergeWorkflow(runner: runner)
        commits = CommitOperationWorkflow(runner: runner)
        stopped = StoppedOperationWorkflow(runner: runner, editor: session.editor)
        let context = { [weak self] in self?.context ?? OperationContext() }
        let notice: (OperationStatus.Notice) -> Void = { [weak self] notice in self?.status.show(notice) }
        branches.context = context
        branches.notice = notice
        stashes.context = context
        stashes.notice = notice
        tags.context = context
        tags.notice = notice
        commits.context = context
        commits.notice = notice
        stopped.context = context
        merging.context = context
        runner.willPerform = { [weak self] in self?.status.dismissNotice() }
        status.continueOperation = { [weak self] in self?.stopped.continueOperation(from: self?.actingWindow) }
        status.skip = { [weak self] in self?.stopped.skip(from: self?.actingWindow) }
        status.abort = { [weak self] in self?.stopped.abort(from: self?.actingWindow) }
    }

    /// Once the window exists: where a failure shows, on the window the command was started from
    /// while it's open, and how to reach the working area, where an edit is made.
    func connect(
        window: @escaping () -> NSWindow?,
        failureSheet: GitFailureSheetPresenter,
        goToUncommittedChanges: @escaping () -> Void
    ) {
        repositoryWindow = window
        let repository = runner.commands.repository
        runner.present = { failure, source, retry, nextSteps in
            guard let target = source?.isVisible == true ? source : window() else { return }
            failureSheet.present(failure, repository: repository, on: target, wasOpenedByUser: false, retry: retry, nextSteps: nextSteps)
        }
        branches.repositoryWindow = window
        stashes.repositoryWindow = window
        tags.repositoryWindow = window
        merging.repositoryWindow = window
        commits.repositoryWindow = window
        commits.goToUncommittedChanges = goToUncommittedChanges
        // Editing the last commit is amending it.
        commits.amendLastCommit = { [session] in
            goToUncommittedChanges()
            if !session.editor.isAmending {
                session.committing.toggleAmend()
            }
        }
        stopped.repositoryWindow = window
    }

    /// The sidebar's context menus, double-click and drag, and the history's context menu and
    /// selection, which the menu bar's commands act on.
    func attach(sidebar: SidebarModel, commitColumns: CommitColumnsCoordinator, remotes: RemotesCoordinator) {
        let history = commitColumns.history
        sidebarSelection = { [weak sidebar] in sidebar?.selection }
        selectInSidebar = { [weak sidebar] id in sidebar?.selection = id }
        selectedCommit = { [weak history] in history?.selectedCommit }
        // The working area's row shows only above the checked-out branch's history.
        historyShowsCheckedOutBranch = { [weak history] in history?.workingArea != nil }
        commitColumns.onCommitSelected = { [weak self] commit in self?.commitSelected(commit) }
        history.operationMenuItems = { [weak self, weak history] commit in
            guard let self else { return [] }
            return OperationHistoryMenu.items(for: commit, isInCheckedOutHistory: history?.workingArea != nil, in: self)
        }
        sidebar.menuItems = { [weak self, weak remotes] id in
            guard let self else { return [] }
            return OperationSidebarMenu.items(for: id, in: self) + (remotes?.sidebarMenu(for: id) ?? [])
        }
        sidebar.primaryAction = { [weak self] id in self?.primaryAction(id) }
        sidebar.drop = { [weak self] dragged, target in self?.drop(dragged, on: target) }
    }

    /// After each refresh.
    func show(_ snapshot: RepositorySnapshot, refs: [Ref], contents: SidebarContents?) {
        let files = snapshot.status.files.filter { $0.state != .ignored }
        context = OperationContext(
            head: snapshot.status.branch,
            refs: refs,
            contents: contents,
            operation: snapshot.operation,
            conflicts: files.count { if case .conflicted = $0.state { true } else { false } },
            hasChanges: !files.isEmpty,
            hasTrackedChanges: files.contains { $0.state != .untracked }
        )
        commits.ancestry.show(head: snapshot.status.branch.commit)
        status.show(StoppedOperation(
            snapshot.operation,
            branch: snapshot.status.branch.name,
            conflicts: context.conflicts,
            editing: StoppedOperation.editedCommit(gitDirectory: gitDirectory)
        ))
    }

    /// Looked up ahead, so the menus know whether it can be reworded or edited as they open.
    func commitSelected(_ commit: Commit?) {
        if let commit {
            commits.ancestry.lookUp(commit.hash)
        }
    }

    /// The menu bar's commands reach the operations from anywhere in the window.
    func target(forAction action: Selector) -> Any? {
        OperationMenuCommands.actions.contains(action) ? menuCommands : nil
    }

    /// A double-click in the sidebar checks out a branch, or the local branch for a remote one.
    func primaryAction(_ id: SidebarItemID) {
        if let branch = context.branch(id) {
            if !branch.isCheckedOut {
                branches.checkOut(branch.name, from: actingWindow)
            }
        } else if context.remoteBranch(id) != nil {
            branches.checkOut(remoteBranch: id, from: actingWindow)
        }
    }

    /// A branch, remote branch or tag dropped on a branch: merge it in, or rebase it onto that
    /// branch, checking out whichever branch changes first, from a menu at the pointer.
    func drop(_ dragged: SidebarItemID, on target: SidebarItemID) {
        guard let draggedRevision = context.revision(dragged), let targetRevision = context.revision(target) else { return }
        let draggedName = draggedRevision.name
        let targetName = targetRevision.name
        let checkedOut = context.checkedOutBranch
        let window = actingWindow
        var items: [NSMenuItem] = []
        if context.branch(target) != nil {
            let title = targetName == checkedOut
                ? "Merge “\(draggedName)” into “\(targetName)”"
                : "Check Out “\(targetName)” and Merge “\(draggedName)” into It"
            items.append(ActionMenuItem.make(title: title) { [weak self] in
                self?.merging.merge(draggedRevision, into: targetName == checkedOut ? nil : targetName, from: window)
            })
        }
        if context.branch(dragged) != nil {
            let title = draggedName == checkedOut
                ? "Rebase “\(draggedName)” onto “\(targetName)”"
                : "Check Out “\(draggedName)” and Rebase It onto “\(targetName)”"
            items.append(ActionMenuItem.make(title: title) { [weak self] in
                self?.merging.rebase(draggedName == checkedOut ? nil : draggedName, onto: targetRevision, from: window)
            })
        }
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        let menu = NSMenu()
        items.forEach(menu.addItem)
        let location = NSEvent.mouseLocation
        // Once the drop has finished, since the menu tracks the mouse until it closes, and the drag
        // would wait for it.
        DispatchQueue.main.async {
            menu.popUp(positioning: nil, at: location, in: nil)
        }
    }

    /// The palette gives focus back to the window it was opened over before a command runs.
    var actingWindow: NSWindow? {
        NSApp.keyWindow ?? repositoryWindow()
    }
}

/// A context menu item that runs a closure, for a menu built for one row.
enum ActionMenuItem {
    /// A disabled item says why in its tooltip.
    static func make(title: String, isEnabled: Bool = true, toolTip: String? = nil, handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler)
        let item = NSMenuItem(title: title, action: isEnabled ? #selector(MenuAction.run(_:)) : nil, keyEquivalent: "")
        item.target = action
        // The item holds its target weakly, so it keeps the action alive this way.
        item.representedObject = action
        item.toolTip = toolTip
        return item
    }

    private final class MenuAction: NSObject {
        private let handler: () -> Void

        init(_ handler: @escaping () -> Void) {
            self.handler = handler
        }

        @objc func run(_: Any?) {
            handler()
        }
    }
}
