import AppKit
import os
import SwiftUI

/// The detail column while the history's working area row is selected: the commit message at the
/// top, then the conflicted, staged, unstaged and untracked files, each with its changes. Its
/// changes are read on every refresh while it's shown, since editing a file that's already changed
/// doesn't change what `git status` says.
final class WorkingAreaViewController: NSViewController {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "WorkingArea")

    /// Asks the window to read the repository again, after a command changed it.
    var requestRefresh: (() -> Void)? {
        get { queue.didRun }
        set { queue.didRun = newValue }
    }

    /// For a command the user ran that failed.
    var presentCommandFailure: ((GitFailure) -> Void)? {
        get { queue.presentFailure }
        set { queue.presentFailure = newValue }
    }

    /// For a failure the user asks to see, with a way to try again.
    var showFailure: ((GitFailure, _ retry: @escaping () -> Void) -> Void)? {
        didSet { diff.showFailure = showFailure }
    }

    var openFileWindow: ((FileWindowRequest) -> Void)?

    let diff: DiffViewController
    let editor = CommitMessageEditor()
    let staging: StagingWorkflow
    private let commands: RepositoryCommandRunner
    private let queue = WorkingAreaCommandQueue()
    private lazy var committing = CommitWorkflow(commands: commands, editor: editor, queue: queue)
    private lazy var messageController = NSHostingController(rootView: CommitMessageView(editor: editor))
    /// Set from the message's height at the column's width, as the commit header's is.
    private lazy var messageHeight = messageController.view.heightAnchor.constraint(equalToConstant: 0)
    private let placeholder = WorkingAreaPlaceholder()
    private lazy var placeholderView = NSHostingView(rootView: WorkingAreaPlaceholderView(model: placeholder))
    private(set) var status: RepositoryStatus?
    /// Every file as last read, before the filter.
    private var allFiles: [DiffFile] = []
    private(set) var filter = WorkingAreaFilter.all
    private lazy var filterControl: NSSegmentedControl = {
        let control = NSSegmentedControl(
            labels: WorkingAreaFilter.allCases.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(filterChosen(_:))
        )
        control.controlSize = .small
        control.selectedSegment = filter.rawValue
        let commands: [AppCommand] = [.showAllChanges, .showStagedChanges, .showUnstagedChanges]
        for (segment, command) in commands.enumerated() {
            control.setToolTip("\(command.title) (\(command.shortcut?.displayText ?? ""))", forSegment: segment)
        }
        control.setAccessibilityLabel("Show")
        return control
    }()
    private var isShown = false
    private var reading: Task<Void, Never>?
    private var failure: GitFailure?

    init(commands: RepositoryCommandRunner, diffOptions: DiffOptionsStore, draft: CommitMessage?) {
        self.commands = commands
        diff = DiffViewController(options: diffOptions, workTree: commands.repository.workTree)
        staging = StagingWorkflow(commands: commands, options: diffOptions, queue: queue)
        super.init(nibName: nil, bundle: nil)
        editor.message = draft ?? CommitMessage()
        staging.window = { [weak self] in self?.view.window }
        placeholder.showDetails = { [weak self] in
            guard let self, let failure else { return }
            showFailure?(failure) { [weak self] in self?.read() }
        }
        connectDiff()
        diffOptions.observe(self) { [weak self] _ in self?.read() }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    var onDraftChange: ((CommitMessage) -> Void)? {
        get { editor.onDraftChange }
        set { editor.onDraftChange = newValue }
    }

    /// The message kept for the next commit, which while amending is the one set aside.
    var draft: CommitMessage? {
        editor.draft
    }

    override func loadView() {
        let view = NSView()
        messageController.sizingOptions = []
        placeholderView.sizingOptions = []
        addChild(messageController)
        addChild(diff)
        let messageView = messageController.view
        let changesView = diff.view
        for subview in [messageView, changesView, placeholderView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            messageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            messageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageHeight,
            changesView.topAnchor.constraint(equalTo: messageView.bottomAnchor),
            changesView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            changesView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            changesView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholderView.topAnchor.constraint(equalTo: changesView.topAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: changesView.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: changesView.trailingAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: changesView.bottomAnchor),
        ])
        self.view = view
        updatePlaceholder()
        followMessageSize()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateMessageHeight()
    }

    /// After every refresh.
    func show(_ snapshot: RepositorySnapshot) {
        let status = snapshot.status
        self.status = status
        let summary = WorkingAreaSummary(status)
        let branch = status.branch
        let isPushed = branch.upstream != nil && branch.ahead == 0
        editor.repository = CommitMessageEditor.Repository(
            staged: summary.staged,
            conflicts: summary.conflicted,
            hasChanges: !summary.isClean,
            hasCommits: branch.commit != nil,
            isMerging: snapshot.operation == .merging,
            pushedTo: isPushed ? branch.upstream : nil
        )
        committing.head = branch.commit
        if snapshot.operation == .merging {
            committing.offerMergeMessage(in: commands.repository.gitDirectory)
        }
        if isShown {
            read()
        }
    }

    /// Changes are only read while the working area is shown.
    func setShown(_ isShown: Bool) {
        guard isShown != self.isShown else { return }
        self.isShown = isShown
        if isShown {
            read()
        } else {
            reading?.cancel()
        }
    }

    private func read() {
        guard isShown, let status else { return }
        reading?.cancel()
        let options = diff.options.options
        let workTree = commands.repository.workTree
        reading = Task { [weak self, commands] in
            do {
                let started = ContinuousClock.now
                var files = try await WorkingAreaDiff.read(status, options: options, workTree: workTree, readingPatch: commands.readPatch)
                guard let shownWhole = self?.diff.filesShownWhole else { return }
                // Left-out changes the user asked to see stay shown as the working area is read again.
                for index in files.indices where shownWhole.contains(files[index].id) && files[index].patch.content != .shown {
                    files[index] = try await WorkingAreaDiff.readFile(
                        files[index],
                        options: options,
                        workTree: workTree,
                        readingPatch: commands.readPatch
                    )
                }
                guard !Task.isCancelled, let self else { return }
                Self.log.info("Read the working area's \(files.count) files in \(ContinuousClock.now - started, privacy: .public)")
                failure = nil
                allFiles = files
                showFiltered()
                diff.readImagesAgain()
                updatePlaceholder()
            } catch is CancellationError {
                return
            } catch is RepositoryCommandRunner.NoUsableGit {
                return
            } catch let failure as GitReadFailure {
                self?.failure = GitFailure(
                    summary: failure.outputWasUnreadable
                        ? "Locus Git Gui couldn’t read Git’s report on the uncommitted changes."
                        : "Git couldn’t read the uncommitted changes.",
                    arguments: failure.command.arguments,
                    result: failure.result
                )
                self?.updatePlaceholder()
            } catch {
                Self.log.error("Reading the working area failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    func setFilter(_ filter: WorkingAreaFilter) {
        guard filter != self.filter else { return }
        self.filter = filter
        filterControl.selectedSegment = filter.rawValue
        showFiltered()
        diff.canvas.scroll(to: 0)
    }

    private func showFiltered() {
        let shown = allFiles.filter { WorkingAreaGroup($0).map(filter.includes) ?? true }
        let message = allFiles.isEmpty ? WorkingAreaFilter.all.noneShown : filter.noneShown
        guard shown != diff.files || shown.isEmpty else { return }
        diff.show(shown, emptyMessage: message, isSameDiff: true)
    }

    @objc private func filterChosen(_ control: NSSegmentedControl) {
        setFilter(WorkingAreaFilter(rawValue: control.selectedSegment) ?? .all)
    }

    func focusSubject() {
        editor.focusSubject()
    }

    /// What Tab moves focus to in the changes, which is nothing while there are none.
    var focusableChanges: NSView? {
        diff.view.isHidden ? nil : diff.focusableView
    }

    func focusChanges() {
        view.window?.makeFirstResponder(focusableChanges)
    }

    /// Measured again when the amend note comes and goes.
    private func followMessageSize() {
        withObservationTracking {
            _ = editor.amendNote
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateMessageHeight()
                self?.followMessageSize()
            }
        }
    }

    private func updateMessageHeight() {
        let width = view.bounds.width
        guard width > 0 else { return }
        let height = messageController.sizeThatFits(in: NSSize(width: width, height: .greatestFiniteMagnitude)).height
        guard abs(messageHeight.constant - height) >= 0.5 else { return }
        messageHeight.constant = height
        updatePlaceholder()
    }

    private func updatePlaceholder() {
        placeholder.failure = failure?.summary
        placeholderView.isHidden = failure == nil
        // Hidden until the message has its height, for the same reason as the commit detail's
        // changes: shown right under the toolbar, its scroll view leaves a divider up through it.
        diff.view.isHidden = failure != nil || messageHeight.constant < 1
    }
}

/// How the working area fills the diff's buttons and menus.
extension WorkingAreaViewController {
    private func connectDiff() {
        diff.summaryAccessory = filterControl
        diff.describeGroup = { [weak self] group in
            guard let self, let group = WorkingAreaGroup(rawValue: group) else { return ("", []) }
            return (group.title, groupActions(group))
        }
        diff.fileActions = { [weak self] file in self?.fileActions(file) ?? [] }
        diff.hunkActions = { [weak self] file, hunk, lines in self?.hunkActions(file, hunk: hunk, lines: lines) ?? [] }
        diff.readFile = { [weak self] file in
            guard let self else { throw CancellationError() }
            return try await WorkingAreaDiff.readFile(
                file,
                options: diff.options.options,
                workTree: commands.repository.workTree,
                readingPatch: commands.readPatch
            )
        }
        diff.readImage = { [commands] file, isNew in
            try await WorkingAreaImages.read(file, isNew: isNew, workTree: commands.repository.workTree, running: commands.run)
        }
        diff.openFileWindow = { [weak self] file in
            guard let self else { return }
            openFileWindow?(FileWindowRequest(source: .workingArea, file: file, files: diff.files))
        }
        // Space stages or unstages the highlighted file, as it would check a box. Shift-Space still
        // pages up.
        diff.onTypedKey = { [weak self] key in
            guard key == " ", NSApp.currentEvent?.modifierFlags.contains(.shift) != true, let self else { return false }
            toggleFileStaging(nil)
            return true
        }
    }

    /// From the latest status rather than the diff, which isn't read while the working area isn't
    /// shown. Staging needs only their names.
    func files(in groups: Set<WorkingAreaGroup>) -> [DiffFile] {
        guard let status else { return [] }
        return WorkingAreaFiles.list(status).filter { groups.contains($0.group) }.map { entry in
            DiffFile(changed: entry.file, patch: FilePatch(), group: entry.group.rawValue)
        }
    }

    private func groupActions(_ group: WorkingAreaGroup) -> [DiffAction] {
        switch group {
        case .conflicted:
            []
        case .staged:
            [DiffAction(title: AppCommand.unstageAll.title) { [weak self] in self?.unstageAll(nil) }]
        case .unstaged:
            [DiffAction(title: AppCommand.stageAll.title) { [weak self] in
                guard let self else { return }
                staging.stageTracked(excluding: files(in: [.conflicted]))
            }]
        case .untracked:
            [DiffAction(title: AppCommand.stageAll.title) { [weak self] in
                guard let self else { return }
                staging.stageUntracked(files(in: [.untracked]))
            }]
        }
    }

    /// The button that acts goes last, as in a dialog, after one that discards.
    private func fileActions(_ file: DiffFile) -> [DiffAction] {
        let stage = DiffAction(title: "Stage", menuTitle: "Stage File") { [weak self] in self?.staging.stage([file]) }
        let discard = DiffAction(title: "Discard…", menuTitle: "Discard Changes…") { [weak self] in self?.staging.discard(file) }
        switch WorkingAreaGroup(file) {
        case .conflicted:
            return [DiffAction(title: "Mark Resolved", menuTitle: "Mark as Resolved") { [weak self] in self?.staging.stage([file]) }]
        case .staged:
            return [DiffAction(title: "Unstage", menuTitle: "Unstage File") { [weak self] in self?.staging.unstage([file]) }]
        case .unstaged:
            return [discard, stage]
        case .untracked:
            return [DiffAction(title: "Move to Trash…") { [weak self] in self?.staging.discard(file) }, stage]
        case nil:
            return []
        }
    }

    /// Worded for the lines picked in the hunk, when there are any.
    private func hunkActions(_ file: DiffFile, hunk: Int, lines: [Int]) -> [DiffAction] {
        let changedLines = lines.filter { file.patch.hunks[hunk].lines[$0].kind != .context }
        func action(_ operation: StagingWorkflow.Operation, _ verb: String) -> DiffAction {
            let isPicking = !changedLines.isEmpty
            let noun = !isPicking ? "Hunk" : changedLines.count == 1 ? "1 Line" : "\(changedLines.count) Lines"
            let ellipsis = operation == .discard ? "…" : ""
            let reason = staging.whyLinesCantBePicked(operation, of: file, isPicking: isPicking)
            return DiffAction(title: "\(verb) \(noun)\(ellipsis)", isEnabled: reason == nil, toolTip: reason) { [weak self] in
                self?.staging.apply(operation, lines: changedLines, hunk: hunk, of: file)
            }
        }
        switch WorkingAreaGroup(file) {
        case .staged:
            return [action(.unstage, "Unstage")]
        case .unstaged, .untracked:
            return [action(.discard, "Discard"), action(.stage, "Stage")]
        case .conflicted, nil:
            return []
        }
    }
}

/// What the working area says in place of its changes when Git couldn't read them.
@Observable
final class WorkingAreaPlaceholder {
    var failure: String?
    @ObservationIgnored var showDetails: (() -> Void)?
}

struct WorkingAreaPlaceholderView: View {
    let model: WorkingAreaPlaceholder

    var body: some View {
        if let failure = model.failure {
            ContentUnavailableView {
                Label("Changes Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            } actions: {
                Button("Show Details") { model.showDetails?() }
            }
        }
    }
}
