import AppKit
import os

/// The window for one repository.
final class RepositoryWindowController: NSWindowController, NSWindowDelegate {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "RepositoryWindow")

    let repository: Repository
    private let gitChoice: GitChoiceStore
    private lazy var scheduler = RefreshScheduler { [weak self] reason in await self?.refresh(because: reason) }
    private lazy var watcher = RepositoryFileWatcher(repository: repository) { [weak self] in
        self?.scheduler.requestSoon(because: .filesChanged)
    }

    init(repository: Repository, gitChoice: GitChoiceStore) {
        self.repository = repository
        self.gitChoice = gitChoice
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
        // Without a toolbar the subtitle shares the title's line, where a long path pushes it out
        // of sight. A unified toolbar puts it underneath.
        window.toolbar = NSToolbar(identifier: "RepositoryWindow")
        window.toolbarStyle = .unified
        super.init(window: window)
        window.delegate = self
        watcher.start()
        scheduler.requestNow(because: .windowOpened)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// Covers changes FSEvents can't see, such as a `git config` edit outside the repository.
    func windowDidBecomeKey(_: Notification) {
        scheduler.requestNow(because: .windowBecameKey)
    }

    func windowWillClose(_: Notification) {
        watcher.stop()
        scheduler.cancel()
    }

    private func refresh(because reason: RefreshScheduler.Reason) async {
        guard let runner = await gitChoice.runner() else { return }
        let started = ContinuousClock.now
        do {
            let snapshot = try await RepositorySnapshot.read(repository, with: runner)
            show(RepositoryTitleBar(status: snapshot.status, operation: snapshot.operation))
            let elapsed = ContinuousClock.now - started
            let files = snapshot.status.files.count
            Self.log.info("Refreshed \(files) files in \(elapsed, privacy: .public) (\(reason.rawValue, privacy: .public))")
        } catch is CancellationError {
            return
        } catch let failure as RepositorySnapshot.ReadFailure {
            Self.log.error("Status exited \(failure.result.status, privacy: .public)")
        } catch {
            Self.log.error("Status couldn't be read: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    private func show(_ titleBar: RepositoryTitleBar) {
        guard let window else { return }
        window.subtitle = titleBar.subtitle
        window.isDocumentEdited = titleBar.isEdited
    }
}
