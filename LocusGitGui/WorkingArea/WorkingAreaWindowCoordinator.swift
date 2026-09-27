import AppKit

/// A repository's working area window: there's one at most, opening it again brings it forward, and
/// it closes with the repository's window. It's told of every refresh, as the detail column is.
final class WorkingAreaWindowCoordinator {
    var openFileWindow: ((FileWindowRequest, NSWindow?) -> Void)?
    var showFailure: ((GitFailure, NSWindow, _ retry: @escaping () -> Void) -> Void)?
    /// When the window opens, closes, moves or shows other changes.
    var onChange: (() -> Void)?
    private let commands: RepositoryCommandRunner
    private let diffOptions: DiffOptionsStore
    private let diffPlaces: DiffPlaceStore
    private let session: WorkingAreaSession
    private var controller: WorkingAreaWindowController?
    private var snapshot: RepositorySnapshot?
    private weak var repositoryWindow: RepositoryWindowController?

    init(
        commands: RepositoryCommandRunner,
        diffOptions: DiffOptionsStore,
        diffPlaces: DiffPlaceStore,
        session: WorkingAreaSession,
        repositoryWindow: RepositoryWindowController
    ) {
        self.commands = commands
        self.diffOptions = diffOptions
        self.diffPlaces = diffPlaces
        self.session = session
        self.repositoryWindow = repositoryWindow
    }

    var window: NSWindow? {
        controller?.window
    }

    /// As it was left when `record` says, and otherwise cascaded from the window it was opened from.
    func show(from sourceWindow: NSWindow?, repositoryName: String, record: OpenWindows.WorkingAreaWindow? = nil) {
        if let controller {
            controller.showWindow(nil)
            return
        }
        let workingArea = WorkingAreaViewController(
            commands: commands,
            diffOptions: diffOptions,
            diffPlaces: diffPlaces,
            session: session
        )
        let controller = WorkingAreaWindowController(workingArea: workingArea, repositoryName: repositoryName)
        controller.repositoryWindow = repositoryWindow
        workingArea.openFileWindow = { [weak self, weak controller] request in self?.openFileWindow?(request, controller?.window) }
        workingArea.showFailure = { [weak self, weak controller] failure, retry in
            guard let window = controller?.window else { return }
            self?.showFailure?(failure, window, retry)
        }
        controller.onClose = { [weak self] in
            self?.controller = nil
            self?.onChange?()
        }
        if let record {
            workingArea.setFilter(record.filter)
        }
        if let snapshot {
            workingArea.show(snapshot)
        }
        self.controller = controller
        if let window = controller.window {
            OpenedWindowPlacement.place(window, at: record?.frame, cascadingFrom: sourceWindow)
        }
        controller.showWindow(nil)
        controller.onChange = { [weak self] in self?.onChange?() }
        workingArea.onFilterChange = { [weak self] in self?.onChange?() }
        onChange?()
    }

    var record: OpenWindows.WorkingAreaWindow? {
        controller.map { OpenWindows.WorkingAreaWindow(frame: $0.window?.frameDescriptor, filter: $0.workingArea.filter) }
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
