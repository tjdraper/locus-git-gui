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
    let commands: RepositoryCommandRunner
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
    private(set) lazy var filterControl: NSSegmentedControl = {
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
