import AppKit

/// Keeps one window per repository. Opening a repository that is already open brings its window
/// forward instead of opening a second.
final class RepositoryWindowCoordinator {
    private let gitChoice: GitChoiceStore
    private let checkForMissingGit: () -> Void
    private var controllers: [String: RepositoryWindowController] = [:]
    /// Kept after a window closes, so reopening the repository later in the session still shows
    /// what ran before.
    private var logs: [String: GitCommandLog] = [:]
    private var cascadePoint = NSPoint.zero

    init(gitChoice: GitChoiceStore, checkForMissingGit: @escaping () -> Void) {
        self.gitChoice = gitChoice
        self.checkForMissingGit = checkForMissingGit
    }

    func show(_ repository: Repository) {
        let key = repository.workTree.standardizedFileURL.path
        if let existing = controllers[key] {
            existing.showWindow(nil)
            return
        }

        let log = logs[key] ?? GitCommandLog()
        logs[key] = log
        let controller = RepositoryWindowController(commands: RepositoryCommandRunner(
            repository: repository,
            log: log,
            gitChoice: gitChoice,
            checkForMissingGit: checkForMissingGit
        ))
        guard let window = controller.window else { return }
        if controllers.isEmpty {
            window.center()
            cascadePoint = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        } else {
            cascadePoint = window.cascadeTopLeft(from: cascadePoint)
        }
        controllers[key] = controller
        controller.showWindow(nil)

        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSWindow.willCloseNotification, object: window) {
                self?.controllers[key] = nil
                break
            }
        }
    }
}
