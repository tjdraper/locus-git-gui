import AppKit

/// A repository's working area window: there's one at most, opening it again brings it forward, and
/// it closes with the repository's window. It's told of every refresh, as the detail column is.
final class WorkingAreaWindowCoordinator {
    var openFileWindow: ((FileWindowRequest, NSWindow?) -> Void)?
    var showFailure: ((GitFailure, NSWindow, _ retry: @escaping () -> Void) -> Void)?
    private let commands: RepositoryCommandRunner
    private let diffOptions: DiffOptionsStore
    private let session: WorkingAreaSession
    private var controller: WorkingAreaWindowController?
    private var snapshot: RepositorySnapshot?
    private weak var repositoryWindow: RepositoryWindowController?

    init(
        commands: RepositoryCommandRunner,
        diffOptions: DiffOptionsStore,
        session: WorkingAreaSession,
        repositoryWindow: RepositoryWindowController
    ) {
        self.commands = commands
        self.diffOptions = diffOptions
        self.session = session
        self.repositoryWindow = repositoryWindow
    }

    var window: NSWindow? {
        controller?.window
    }

    /// Cascaded from the window it was opened from.
    func show(from sourceWindow: NSWindow?, repositoryName: String) {
        if let controller {
            controller.showWindow(nil)
            return
        }
        let workingArea = WorkingAreaViewController(commands: commands, diffOptions: diffOptions, session: session)
        let controller = WorkingAreaWindowController(workingArea: workingArea, repositoryName: repositoryName)
        controller.repositoryWindow = repositoryWindow
        workingArea.openFileWindow = { [weak self, weak controller] request in self?.openFileWindow?(request, controller?.window) }
        workingArea.showFailure = { [weak self, weak controller] failure, retry in
            guard let window = controller?.window else { return }
            self?.showFailure?(failure, window, retry)
        }
        controller.onClose = { [weak self] in self?.controller = nil }
        if let snapshot {
            workingArea.show(snapshot)
        }
        self.controller = controller
        if let window = controller.window, let sourceWindow {
            let topLeft = window.cascadeTopLeft(from: NSPoint(x: sourceWindow.frame.minX, y: sourceWindow.frame.maxY))
            window.cascadeTopLeft(from: topLeft)
        } else {
            controller.window?.center()
        }
        controller.showWindow(nil)
    }

    func showRepositoryName(_ name: String) {
        controller?.window?.subtitle = name
    }

    /// After every refresh.
    func show(_ snapshot: RepositorySnapshot) {
        self.snapshot = snapshot
        controller?.workingArea.show(snapshot)
    }

    func close() {
        controller?.close()
        controller = nil
    }
}
