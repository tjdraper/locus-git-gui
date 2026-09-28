import AppKit
import os
import SwiftUI

/// A repository's conflicted files in a window of their own: the list of them, and for the one
/// picked, each side's version above the result to edit, or the versions to choose between. Edits
/// reach the file when they're saved, when the file is marked resolved, when another file is picked,
/// and when the window closes or the app quits, so none are lost.
final class ConflictWindowController: NSWindowController, NSWindowDelegate {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "ConflictWindow")
    private static let contentSize = NSSize(width: 1200, height: 820)
    private static let listWidth: CGFloat = 240

    let list = ConflictFileList()
    let editor: ConflictEditorViewController
    var onClose: (() -> Void)?
    /// When the window moves or shows another file, for the repository to remember.
    var onChange: (() -> Void)?
    /// For a failure the user asks to see, with a way to try again.
    var showFailure: ((GitFailure, _ retry: @escaping () -> Void) -> Void)?
    /// Names each side for the file shown, given what Git wrote after its first conflict.
    var sideNames: (_ theirsLabel: String?) -> ConflictSideNames = { _ in ConflictSideNames(ours: "HEAD", theirs: "Theirs") }
    weak var repositoryWindow: RepositoryWindowController?
    let commands: RepositoryCommandRunner
    private let workflow: ConflictResolutionWorkflow
    /// The file shown, as it was read.
    private var contents: ConflictFileContents?
    private var reading: Task<Void, Never>?
    private var readFailure: GitReadFailure?

    init(commands: RepositoryCommandRunner, queue: WorkingAreaCommandQueue, operationStatus: OperationStatus, repositoryName: String) {
        self.commands = commands
        workflow = ConflictResolutionWorkflow(commands: commands, queue: queue)
        editor = ConflictEditorViewController(operationStatus: operationStatus)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // Brought back with its repository's window, rather than on its own after a relaunch.
        window.isRestorable = false
        // Kept apart from repository windows, which would otherwise take it as a tab.
        window.tabbingIdentifier = "ConflictWindow"
        window.title = "Conflicts"
        window.subtitle = repositoryName
        // Gives the title bar room for the subtitle.
        window.toolbar = NSToolbar(identifier: "ConflictWindow")
        window.toolbarStyle = .unified
        super.init(window: window)
        let split = NSSplitViewController()
        let listController = NSHostingController(rootView: ConflictFileListView(list: list))
        listController.sizingOptions = []
        let listItem = NSSplitViewItem(viewController: listController)
        listItem.minimumThickness = 180
        listItem.maximumThickness = 420
        listItem.canCollapse = false
        listItem.holdingPriority = .defaultLow + 10
        split.addSplitViewItem(listItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: editor))
        let hasPlacedList = UserDefaults.standard.object(forKey: "NSSplitView Subview Frames ConflictWindowList") != nil
        split.splitView.autosaveName = "ConflictWindowList"
        window.contentViewController = split
        window.setContentSize(Self.contentSize)
        if !hasPlacedList {
            split.splitView.setPosition(Self.listWidth, ofDividerAt: 0)
        }
        window.delegate = self
        connect()
        // A selector rather than an async sequence, which would deliver it after the app had quit.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    private func connect() {
        workflow.window = { [weak self] in self?.window }
        list.onSelectionChange = { [weak self] path in self?.select(path) }
        list.onOpen = { [weak self] in self?.editor.focusResult() }
        editor.onEditedChange = { [weak self] isEdited in self?.window?.isDocumentEdited = isEdited }
        let state = editor.state
        state.save = { [weak self] in self?.save() }
        state.markResolved = { [weak self] in self?.markResolved() }
        state.choose = { [weak self] choice in self?.choose(choice) }
        state.showFailureDetails = { [weak self] in
            guard let self, let readFailure else { return }
            let failure = GitFailure(
                summary: "Git couldn’t read this file’s conflict.",
                arguments: readFailure.command.arguments,
                result: readFailure.result
            )
            showFailure?(failure) { [weak self] in self?.select(self?.list.selection) }
        }
    }

    /// After every refresh: the files with conflicts now. When the file shown is resolved, the next
    /// one is shown; while it isn't, a change made to it elsewhere is shown, unless there are edits
    /// here the file doesn't have.
    func show(_ conflicted: [(path: String, conflict: RepositoryStatus.Conflict)]) {
        list.names = sideNames(nil)
        list.show(conflicted)
        let paths = Set(conflicted.map(\.path))
        let selection = list.selection
        if let contents, contents.path == selection, !paths.contains(contents.path) {
            save()
            self.contents = nil
            list.selection = list.conflictedFile(after: contents.path)
        } else if selection == nil || !list.entries.contains(where: { $0.path == selection }) {
            list.selection = list.conflictedPaths.first
        } else if contents?.path == selection {
            reloadFromDiskIfUnedited()
        }
        if list.selection == nil {
            showNothingToResolve()
        }
    }

    /// Picks `path` in the list, when it has a conflict.
    func select(file path: String) {
        guard list.conflictedPaths.contains(path) else { return }
        list.selection = path
    }

    private func showNothingToResolve() {
        // Empty until the first refresh lists the files, which follows a command that stopped on
        // conflicts moments after the window opens for it.
        editor.showMessage(list.entries.isEmpty ? "" : "Every conflict is resolved.")
    }

    private func select(_ path: String?) {
        save()
        reading?.cancel()
        contents = nil
        window?.isDocumentEdited = false
        onChange?()
        guard let path else {
            showNothingToResolve()
            return
        }
        guard list.conflictedPaths.contains(path) else {
            editor.showMessage("“\((path as NSString).lastPathComponent)” is resolved.")
            return
        }
        editor.showReading()
        reading = Task { [weak self, commands] in
            do {
                let started = ContinuousClock.now
                let contents = try await ConflictFileContents.read(path, workTree: commands.repository.workTree, running: commands.run)
                let markers = await Self.findConflicts(in: contents)
                guard !Task.isCancelled, let self, list.selection == path else { return }
                show(contents, markers: markers)
                let size = contents.result.text?.utf8.count ?? 0
                let count = markers.conflicts.count
                let elapsed = ContinuousClock.now - started
                Self.log.info("Read a conflicted file of \(size) bytes with \(count) conflicts in \(elapsed, privacy: .public)")
            } catch is CancellationError {
                return
            } catch is RepositoryCommandRunner.NoUsableGit {
                return
            } catch let failure as GitReadFailure {
                guard let self, list.selection == path else { return }
                readFailure = failure
                editor.showFailure("Git couldn’t read this file’s conflict.")
            } catch {
                Self.log.error("Reading a conflict failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    /// Away from the main actor, since a large file takes a moment to read through.
    @concurrent
    private static func findConflicts(in contents: ConflictFileContents) async -> ConflictMarkers {
        ConflictMarkers(parsing: contents.result.text ?? "", markerSize: contents.markerSize)
    }

    private func show(_ contents: ConflictFileContents, markers: ConflictMarkers) {
        self.contents = contents
        editor.show(contents, markers: markers, names: sideNames(markers.conflicts.first?.theirsLabel))
    }

    private func reloadFromDiskIfUnedited() {
        guard let contents, contents.isEditable, !editor.result.isEdited else { return }
        let url = commands.repository.workTree.appending(path: contents.path, directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: url), let text = String(bytes: data, encoding: .utf8), text != editor.result.text else {
            return
        }
        editor.reload(text)
    }

    /// Whether there was nothing to save or it was saved.
    @discardableResult
    func save() -> Bool {
        guard let contents, editor.result.isEdited else { return true }
        guard workflow.save(editor.result.text, to: contents.path) else { return false }
        editor.result.markSaved()
        return true
    }

    func markResolved() {
        guard let contents, contents.isEditable, save() else { return }
        workflow.markResolved(contents.path, conflictsLeft: editor.result.conflictCount)
    }

    private func choose(_ choice: ConflictVersionChoice) {
        guard let contents else { return }
        workflow.choose(choice, for: contents.path, stages: contents.stages)
    }

    /// Taking a side of a file that side deleted is deleting it.
    func chooseVersion(ofOurs isOurs: Bool) {
        guard let contents else { return }
        let hasVersion = isOurs ? contents.stages.ours != nil : contents.stages.theirs != nil
        choose(hasVersion ? (isOurs ? .ours : .theirs) : .delete)
    }

    var record: OpenWindows.ConflictWindow {
        OpenWindows.ConflictWindow(frame: window?.frameDescriptor, file: list.selection, showsBase: editor.state.showsBase)
    }

    func restore(_ record: OpenWindows.ConflictWindow) {
        editor.setBaseShown(record.showsBase)
        if let file = record.file {
            select(file: file)
        }
    }

    func windowWillReturnUndoManager(_: NSWindow) -> UndoManager? {
        editor.result.undo
    }

    func windowWillClose(_: Notification) {
        save()
        reading?.cancel()
        onClose?()
    }

    func windowDidMove(_: Notification) {
        onChange?()
    }

    func windowDidResize(_: Notification) {
        onChange?()
    }

    /// Windows aren't closed when the app quits, so the edits are saved here.
    @objc private func applicationWillTerminate(_: Notification) {
        save()
    }

    /// Commands for the whole repository, such as Continue, reach its window.
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if RepositoryWindowController.repositoryActions.contains(action) {
            return repositoryWindow?.repositoryTarget(for: action)
        }
        return super.supplementalTarget(forAction: action, sender: sender)
    }
}
