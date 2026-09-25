import AppKit

/// Keeps one window per repository. Opening a repository that is already open brings its window
/// forward instead of opening a second.
final class RepositoryWindowCoordinator {
    private let gitChoice: GitChoiceStore
    private var controllers: [String: RepositoryWindowController] = [:]
    private var cascadePoint = NSPoint.zero

    init(gitChoice: GitChoiceStore) {
        self.gitChoice = gitChoice
    }

    func show(_ repository: Repository) {
        let key = repository.workTree.standardizedFileURL.path
        if let existing = controllers[key] {
            existing.showWindow(nil)
            return
        }

        let controller = RepositoryWindowController(repository: repository, gitChoice: gitChoice)
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
