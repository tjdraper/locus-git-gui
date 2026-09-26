import AppKit

/// One commit in a window of its own, with the same header and changes as the detail column.
final class CommitWindowController: NSWindowController, NSWindowDelegate {
    private static let contentSize = NSSize(width: 720, height: 760)

    let detail: CommitDetailViewController
    var onClose: (() -> Void)?
    private let repositoryName: String
    private let failureSheet = GitFailureSheetPresenter()
    private let repository: Repository

    init(repository: Repository, repositoryName: String, run: @escaping (GitCommand) async throws -> ChildProcess.Result) {
        self.repository = repository
        self.repositoryName = repositoryName
        detail = CommitDetailViewController(run: run)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // Commits aren't brought back after a relaunch, only repositories.
        window.isRestorable = false
        // Kept apart from repository windows, which would otherwise take them as tabs.
        window.tabbingIdentifier = "CommitWindow"
        // Gives the title bar room for the subtitle.
        window.toolbar = NSToolbar(identifier: "CommitWindow")
        window.toolbarStyle = .unified
        super.init(window: window)
        window.contentViewController = detail
        window.setContentSize(Self.contentSize)
        window.delegate = self
        detail.showFailure = { [weak self] failure, retry in
            guard let self, let window = self.window else { return }
            failureSheet.present(failure, repository: repository, on: window, wasOpenedByUser: true, retry: retry)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    var commit: Commit? {
        detail.commit
    }

    func show(_ commit: Commit, labels: [CommitRefLabel]) {
        detail.show(commit, labels: labels)
        window?.title = commit.subject.isEmpty ? "(No message)" : commit.subject
        window?.subtitle = "\(commit.hash.prefix(7)) · \(repositoryName)"
    }

    func windowWillClose(_: Notification) {
        onClose?()
    }

    @objc func copyCommitHash(_: Any?) {
        guard let commit else { return }
        putOnPasteboard(commit.hash)
    }

    @objc func copyCommitSubject(_: Any?) {
        guard let commit else { return }
        putOnPasteboard(commit.subject)
    }

    private func putOnPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension CommitWindowController: CommandPaletteDestinationSource {
    /// A commit window has no sidebar to jump around in.
    var paletteDestinations: [CommandPaletteDestination] {
        []
    }

    func paletteChoices(for command: AppCommand) -> [CommandPaletteDestination]? {
        switch command {
        case .goToParentCommit:
            CommitPaletteChoices.parents(
                of: commit,
                title: { String($0.prefix(7)) },
                goTo: { [weak self] hash in self?.detail.goToCommit?(hash) }
            )
        case .revealCommitInSidebar:
            CommitPaletteChoices.labels(detail.labels) { [weak self] item in self?.detail.reveal?(item) }
        default:
            nil
        }
    }
}
