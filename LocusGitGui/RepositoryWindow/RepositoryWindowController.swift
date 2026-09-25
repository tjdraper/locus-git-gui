import AppKit
import os

/// The window for one repository.
final class RepositoryWindowController: NSWindowController, NSWindowDelegate {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "RepositoryWindow")

    let repository: Repository
    private let commands: RepositoryCommandRunner
    private let failureSheet = GitFailureSheetPresenter()
    private lazy var toolbar = RepositoryToolbar { [weak self] in self?.showBackgroundFailure() }
    private lazy var gitLogWindow = GitLogWindowPresenter(log: commands.log, repository: repository)
    private lazy var scheduler = RefreshScheduler { [weak self] reason in await self?.refresh(because: reason) }
    private lazy var watcher = RepositoryFileWatcher(repository: repository) { [weak self] in
        self?.scheduler.requestSoon(because: .filesChanged)
    }
    /// The latest failure of something the app did by itself, shown as the toolbar warning until a
    /// later attempt succeeds.
    private var backgroundFailure: GitFailure?

    init(commands: RepositoryCommandRunner) {
        self.commands = commands
        repository = commands.repository
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = (repository.workTree.path as NSString).abbreviatingWithTildeInPath
        // The proxy icon: ⌘-click the title for the path, or drag the folder out.
        window.representedURL = repository.workTree
        window.isReleasedWhenClosed = false
        super.init(window: window)
        // A toolbar also moves the subtitle under the title, where a long path can't push it out
        // of sight.
        window.toolbar = toolbar.toolbar
        window.toolbarStyle = .unified
        window.delegate = self
        watcher.start()
        scheduler.requestNow(because: .windowOpened)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// Reached through the responder chain from View > Show Git Log.
    @objc func showGitLog(_: Any?) {
        gitLogWindow.show()
    }

    /// Covers changes FSEvents can't see, such as a `git config` edit outside the repository.
    func windowDidBecomeKey(_: Notification) {
        scheduler.requestNow(because: .windowBecameKey)
    }

    func windowWillClose(_: Notification) {
        watcher.stop()
        scheduler.cancel()
        gitLogWindow.close()
    }

    private func refresh(because reason: RefreshScheduler.Reason) async {
        let started = ContinuousClock.now
        do {
            let snapshot = try await RepositorySnapshot.read(repository, running: commands.run)
            show(RepositoryTitleBar(status: snapshot.status, operation: snapshot.operation))
            clearBackgroundFailure()
            let elapsed = ContinuousClock.now - started
            let files = snapshot.status.files.count
            Self.log.info("Refreshed \(files) files in \(elapsed, privacy: .public) (\(reason.rawValue, privacy: .public))")
        } catch is CancellationError {
            return
        } catch is RepositoryCommandRunner.NoUsableGit {
            return
        } catch let failure as RepositorySnapshot.ReadFailure {
            show(.unavailable)
            reportBackgroundFailure(GitFailure(
                summary: failure.outputWasUnreadable
                    ? "Locus Git Gui couldn’t read Git’s report on this repository’s status."
                    : "Git couldn’t read this repository’s status.",
                arguments: RepositoryStatus.command.arguments,
                result: failure.result
            ))
        } catch let ChildProcess.Failure.couldNotStart(error) {
            // Git never ran, so there is no output of its own. The system's reason stands in for it.
            show(.unavailable)
            reportBackgroundFailure(GitFailure(
                summary: "Git couldn’t start in this repository’s folder.",
                arguments: RepositoryStatus.command.arguments,
                result: ChildProcess.Result(status: -1, standardOutput: Data(), standardError: Data(error.localizedDescription.utf8))
            ))
        } catch {
            Self.log.error("Refresh failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    private func show(_ titleBar: RepositoryTitleBar) {
        guard let window else { return }
        window.subtitle = titleBar.subtitle
        window.isDocumentEdited = titleBar.isEdited
    }

    private func reportBackgroundFailure(_ failure: GitFailure) {
        backgroundFailure = failure
        toolbar.showWarning(failure.summary)
        Self.log.error("Background refresh failed with status \(failure.result.status, privacy: .public)")
    }

    private func clearBackgroundFailure() {
        guard backgroundFailure != nil else { return }
        backgroundFailure = nil
        toolbar.hideWarning()
    }

    private func showBackgroundFailure() {
        guard let backgroundFailure, let window else { return }
        failureSheet.present(backgroundFailure, repository: repository, on: window, wasOpenedByUser: true) { [weak self] in
            self?.scheduler.requestNow(because: .retried)
        }
    }
}
