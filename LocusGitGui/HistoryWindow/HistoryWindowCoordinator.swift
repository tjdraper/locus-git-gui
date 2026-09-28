import AppKit

/// The history windows opened from one repository's window. One window per branch, tag, remote or
/// stash: opening one that's already open brings it forward. They close with the repository's
/// window.
final class HistoryWindowCoordinator {
    var reveal: ((SidebarItemID) -> Void)?
    var openCommit: ((Commit, NSWindow?) -> Void)?
    var openFileWindow: ((FileWindowRequest, NSWindow?) -> Void)?
    /// When a window opens, closes, moves or its history's place changes.
    var onChange: (() -> Void)?
    private let commands: RepositoryCommandRunner
    private let diffOptions: DiffOptionsStore
    private let diffPlaces: DiffPlaceStore
    private weak var repositoryWindow: RepositoryWindowController?
    private var controllers: [HistoryWindowController] = []
    /// As of the last refresh, for a window opened between refreshes.
    private var refs: [Ref]?
    private var head: String?
    private var contents: SidebarContents?
    private var labels: [String: [CommitRefLabel]] = [:]

    init(
        commands: RepositoryCommandRunner,
        diffOptions: DiffOptionsStore,
        diffPlaces: DiffPlaceStore,
        repositoryWindow: RepositoryWindowController
    ) {
        self.commands = commands
        self.diffOptions = diffOptions
        self.diffPlaces = diffPlaces
        self.repositoryWindow = repositoryWindow
    }

    /// As it was left when `record` says, and otherwise cascaded from the last one opened, or the
    /// window it was opened from.
    func show(_ item: SidebarItemID, from sourceWindow: NSWindow?, repositoryName: String, record: OpenWindows.HistoryWindow? = nil) {
        if let existing = controllers.first(where: { $0.item == item }) {
            existing.showWindow(nil)
            return
        }
        let controller = HistoryWindowController(
            item: item,
            contents: contents,
            place: record?.place,
            repositoryName: repositoryName,
            commands: commands,
            diffOptions: diffOptions,
            diffPlaces: diffPlaces
        )
        controller.repositoryWindow = repositoryWindow
        controller.detail.messageFormat = repositoryWindow?.messageFormat
        connect(controller)
        controllers.append(controller)
        if let refs, let contents {
            controller.show(refs: refs, head: head, contents: contents)
        }
        controller.showLabels(labels)
        if let window = controller.window {
            OpenedWindowPlacement.place(window, at: record?.frame, cascadingFrom: controllers.dropLast().last?.window ?? sourceWindow)
        }
        controller.showWindow(nil)
        controller.onChange = { [weak self] in self?.onChange?() }
        onChange?()
    }

    private func connect(_ controller: HistoryWindowController) {
        controller.history.reveal = { [weak self] id in self?.reveal?(id) }
        controller.detail.reveal = { [weak self] id in self?.reveal?(id) }
        controller.history.onOpen = { [weak self, weak controller] commit in self?.openCommit?(commit, controller?.window) }
        controller.detail.openFileWindow = { [weak self, weak controller] request in
            self?.openFileWindow?(request, controller?.window)
        }
        controller.onClose = { [weak self, weak controller] in
            self?.controllers.removeAll { $0 === controller }
            self?.onChange?()
        }
    }

    var records: [OpenWindows.HistoryWindow] {
        controllers.map(\.record)
    }

    /// After every refresh.
    func show(refs: [Ref], head: String?, contents: SidebarContents, labels: [String: [CommitRefLabel]]) {
        self.refs = refs
        self.head = head
        self.contents = contents
        self.labels = labels
        for controller in controllers {
            controller.show(refs: refs, head: head, contents: contents)
            controller.showLabels(labels)
        }
    }

    func showRepositoryName(_ name: String) {
        for controller in controllers {
            controller.showRepositoryName(name)
        }
    }

    func closeAll() {
        for controller in controllers {
            controller.close()
        }
        controllers.removeAll()
    }
}
