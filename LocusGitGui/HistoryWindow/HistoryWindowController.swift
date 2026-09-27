import AppKit

/// One branch's, tag's, remote's or stash's history in a window of its own, beside the detail of
/// the commit selected in it, as the repository window's last two columns show them.
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    private static let contentSize = NSSize(width: 1100, height: 760)

    let item: SidebarItemID
    let history: HistoryViewController
    let detail: CommitDetailViewController
    var onClose: (() -> Void)?
    /// When the window moves or its history's place changes, for the repository to remember.
    var onChange: (() -> Void)?
    weak var repositoryWindow: RepositoryWindowController?
    private let repository: Repository
    private let failureSheet = GitFailureSheetPresenter()
    private var repositoryName: String
    private var title: HistoryWindowTitle
    private var isGone = false
    /// Where the history was left, until it's first shown.
    private var placeToShow: HistoryPlace?
    private var hasShownHistory = false

    init(
        item: SidebarItemID,
        contents: SidebarContents?,
        place: HistoryPlace?,
        repositoryName: String,
        commands: RepositoryCommandRunner,
        diffOptions: DiffOptionsStore,
        diffPlaces: DiffPlaceStore
    ) {
        self.item = item
        self.repositoryName = repositoryName
        repository = commands.repository
        title = HistoryWindowTitle(item, in: contents)
        placeToShow = place
        history = HistoryViewController(list: HistoryList { command, onOutput in
            try await commands.run(command, onOutput: onOutput)
        })
        detail = CommitDetailViewController(commands: commands, diffOptions: diffOptions, diffPlaces: diffPlaces)
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
        window.tabbingIdentifier = "HistoryWindow"
        // Gives the title bar room for the subtitle.
        window.toolbar = NSToolbar(identifier: "HistoryWindow")
        window.toolbarStyle = .unified
        super.init(window: window)
        window.contentViewController = HistorySplitViewController(history: history, detail: detail)
        window.setContentSize(Self.contentSize)
        // The list rather than Find above it, so the arrow keys move through the commits at once.
        window.initialFirstResponder = history.table
        window.delegate = self
        connectColumns()
        showTitle()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    var record: OpenWindows.HistoryWindow {
        OpenWindows.HistoryWindow(item: item, frame: window?.frameDescriptor, place: placeToShow ?? history.place)
    }

    /// After every refresh. A history whose branch is gone keeps showing what it last read, rather
    /// than the checked-out branch's, which is where the scope falls back to.
    func show(refs: [Ref], head: String?, contents: SidebarContents) {
        title = HistoryWindowTitle(item, in: contents)
        isGone = !contents.contains(item)
        showTitle()
        guard !isGone else { return }
        history.show(
            HistoryScope.resolve(selection: item, refs: refs, contents: contents, head: head),
            isSameSelection: hasShownHistory,
            place: hasShownHistory ? nil : placeToShow
        )
        hasShownHistory = true
        placeToShow = nil
    }

    func showLabels(_ labels: [String: [CommitRefLabel]]) {
        history.showLabels(labels)
        if let commit = detail.commit {
            detail.showLabels(labels[commit.hash] ?? [])
        }
    }

    func showRepositoryName(_ name: String) {
        repositoryName = name
        showTitle()
    }

    /// The repository first in the subtitle, so it's the last thing a narrow window cuts.
    private func showTitle() {
        window?.title = title.name
        window?.subtitle = [repositoryName, title.kind, isGone ? title.gone : nil].compactMap(\.self).joined(separator: " · ")
    }

    private func connectColumns() {
        history.onSelect = { [weak self] selected in
            guard let self else { return }
            if case let .commit(commit) = selected {
                detail.show(commit, labels: history.labels(of: commit))
            } else {
                detail.show(nil, labels: [])
            }
        }
        history.onPlaceChange = { [weak self] _ in self?.onChange?() }
        detail.goToCommit = { [weak self] hash in self?.history.goToCommit(hash) }
        let showFailure: (GitFailure, @escaping () -> Void) -> Void = { [weak self] failure, retry in
            guard let self, let window else { return }
            failureSheet.present(failure, repository: repository, on: window, wasOpenedByUser: true, retry: retry)
        }
        history.showFailure = showFailure
        detail.showFailure = showFailure
    }

    func windowWillClose(_: Notification) {
        onClose?()
    }

    func windowDidMove(_: Notification) {
        onChange?()
    }

    func windowDidResize(_: Notification) {
        onChange?()
    }

    /// The history's, the commit's and the diff's commands reach them wherever focus is in the
    /// window, and commands for the whole repository reach its window.
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if HistoryViewController.windowActions.contains(action) {
            return history
        }
        if CommitDetailViewController.windowActions.contains(action) {
            return detail
        }
        if DiffViewController.windowActions.contains(action) {
            return detail.diff
        }
        if RepositoryWindowController.repositoryActions.contains(action) {
            return repositoryWindow
        }
        return super.supplementalTarget(forAction: action, sender: sender)
    }
}

extension HistoryWindowController: CommandPaletteDestinationSource {
    /// A history window has no sidebar to jump around in.
    var paletteDestinations: [CommandPaletteDestination] {
        []
    }

    func paletteChoices(for command: AppCommand) -> [CommandPaletteDestination]? {
        switch command {
        case .goToParentCommit: history.parentChoices
        case .revealCommitInSidebar: history.labelChoices
        default: nil
        }
    }
}
