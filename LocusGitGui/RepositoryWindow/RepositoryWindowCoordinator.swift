import AppKit

/// Keeps one window per repository. Opening a repository that is already open brings its window
/// forward instead of opening a second.
final class RepositoryWindowCoordinator {
    private let gitChoice: GitChoiceStore
    private let logs: GitCommandLogs
    private let checkForMissingGit: () -> Void
    private var controllers: [String: RepositoryWindowController] = [:]
    private var cascadePoint = NSPoint.zero

    init(gitChoice: GitChoiceStore, logs: GitCommandLogs, checkForMissingGit: @escaping () -> Void) {
        self.gitChoice = gitChoice
        self.logs = logs
        self.checkForMissingGit = checkForMissingGit
    }

    var hasOpenWindows: Bool {
        !controllers.isEmpty
    }

    func show(_ repository: Repository) {
        let key = repository.id
        if let existing = controllers[key] {
            existing.showWindow(nil)
            return
        }

        let controller = RepositoryWindowController(commands: RepositoryCommandRunner(
            repository: repository,
            log: logs.log(for: repository),
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
