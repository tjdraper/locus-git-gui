import AppKit

/// The file windows opened from one repository's window, its commit windows included. One window
/// per file in a commit, and per file in each of the working area's groups: opening one that's
/// already open brings it forward. They close with the repository's window.
final class FileWindowCoordinator {
    private let commands: RepositoryCommandRunner
    private let diffOptions: DiffOptionsStore
    private var controllers: [FileWindowController] = []
    private weak var repositoryWindow: RepositoryWindowController?

    init(commands: RepositoryCommandRunner, diffOptions: DiffOptionsStore, repositoryWindow: RepositoryWindowController) {
        self.commands = commands
        self.diffOptions = diffOptions
        self.repositoryWindow = repositoryWindow
    }

    /// Cascaded from the window it was opened from.
    func show(_ request: FileWindowRequest, from sourceWindow: NSWindow?, repositoryName: String) {
        let isShowing = { (controller: FileWindowController) in
            controller.source == request.source && controller.file == request.file.id
        }
        if let existing = controllers.first(where: isShowing) {
            existing.showWindow(nil)
            return
        }
        let controller = FileWindowController(
            request,
            repositoryName: repositoryName,
            commands: commands,
            diffOptions: diffOptions
        )
        controller.repositoryWindow = repositoryWindow
        controller.onClose = { [weak self, weak controller] in
            self?.controllers.removeAll { $0 === controller }
        }
        controllers.append(controller)
        if let window = controller.window {
            if let sourceWindow {
                let topLeft = window.cascadeTopLeft(from: NSPoint(x: sourceWindow.frame.minX, y: sourceWindow.frame.maxY))
                window.cascadeTopLeft(from: topLeft)
            } else {
                window.center()
            }
        }
        controller.showWindow(nil)
    }

    func showRepositoryName(_ name: String) {
        for controller in controllers {
            controller.showRepositoryName(name)
        }
    }

    /// After every refresh, so a working area file's window keeps up with its changes.
    func showWorkingArea(_ files: [DiffFile]) {
        for controller in controllers where controller.source == .workingArea {
            controller.showWorkingArea(files)
        }
    }

    var showsWorkingArea: Bool {
        controllers.contains { $0.source == .workingArea }
    }

    func closeAll() {
        for controller in controllers {
            controller.close()
        }
        controllers.removeAll()
    }
}
