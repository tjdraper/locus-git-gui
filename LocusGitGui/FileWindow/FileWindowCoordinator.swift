import AppKit

/// The file windows opened from one repository's window, its commit windows included. One window
/// per file in a commit: opening one that's already open brings it forward. They close with the
/// repository's window.
final class FileWindowCoordinator {
    private let commands: RepositoryCommandRunner
    private let diffOptions: DiffOptionsStore
    private var controllers: [FileWindowController] = []

    init(commands: RepositoryCommandRunner, diffOptions: DiffOptionsStore) {
        self.commands = commands
        self.diffOptions = diffOptions
    }

    /// Cascaded from the window it was opened from.
    func show(_ request: FileWindowRequest, from sourceWindow: NSWindow?, repositoryName: String) {
        let isShowing = { (controller: FileWindowController) in
            controller.commit.hash == request.commit.hash && controller.path == request.file.changed.path
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

    func closeAll() {
        for controller in controllers {
            controller.close()
        }
        controllers.removeAll()
    }
}
