import AppKit

/// Opens Clone Repository windows from the File menu, the palette, the dashboard and the Open
/// panel. A window that isn't cloning is brought forward rather than opening another, and one that
/// is keeps going while a new one starts the next clone.
final class CloneWindowPresenter {
    private let gitChoice: GitChoiceStore
    private let logs: GitCommandLogs
    private let askpass: AskpassServer
    private let checkForMissingGit: () -> Void
    private let showChecklist: () -> Void
    private let didClone: (URL) -> Void
    private var controllers: [CloneWindowController] = []

    init(
        gitChoice: GitChoiceStore,
        logs: GitCommandLogs,
        askpass: AskpassServer,
        checkForMissingGit: @escaping () -> Void,
        showChecklist: @escaping () -> Void,
        didClone: @escaping (URL) -> Void
    ) {
        self.gitChoice = gitChoice
        self.logs = logs
        self.askpass = askpass
        self.checkForMissingGit = checkForMissingGit
        self.showChecklist = showChecklist
        self.didClone = didClone
    }

    /// Only once there's a Git to clone with. Otherwise the checklist's Git step comes first.
    func show() {
        Task {
            guard await gitChoice.runner() != nil else {
                showChecklist()
                return
            }
            let controller = controllers.first { !$0.isCloning } ?? makeController()
            controller.fillAddressFromClipboard()
            NSApp.activate()
            controller.showWindow(nil)
        }
    }

    private func makeController() -> CloneWindowController {
        let controller = CloneWindowController(
            gitChoice: gitChoice,
            logs: logs,
            askpass: askpass,
            checkForMissingGit: checkForMissingGit
        ) { [didClone] destination in
            didClone(destination)
        }
        if let window = controller.window {
            if let front = controllers.last?.window, front.isVisible {
                window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: front.frame.minX, y: front.frame.maxY)))
            }
            Task { [weak self, weak controller] in
                for await _ in NotificationCenter.default.notifications(named: NSWindow.willCloseNotification, object: window) {
                    self?.controllers.removeAll { $0 === controller }
                    break
                }
            }
        }
        controllers.append(controller)
        return controller
    }
}
