import AppKit

/// The review windows opened from one repository's window: one per review, so opening a review
/// that's already open brings its window forward. They close with the repository's window.
final class ReviewWindowCoordinator {
    private let store: ReviewStore
    private let commands: RepositoryCommandRunner
    private let diffOptions: DiffOptionsStore
    private var controllers: [ReviewWindowController] = []
    private weak var repositoryWindow: RepositoryWindowController?
    /// Where each review's window was left, by the review's id, kept after its window closes.
    var places: [String: ReviewPlace] = [:]
    /// As of the last refresh, for a window opened before the next.
    private var refs: [Ref]?
    private var head: String?

    /// When a window opens, closes, moves or shows something else.
    var onChange: (() -> Void)?
    var rename: ((UUID, NSWindow?) -> Void)?
    var delete: ((UUID, NSWindow?) -> Void)?
    var reviewCommands: ReviewCommands?

    init(
        store: ReviewStore,
        commands: RepositoryCommandRunner,
        diffOptions: DiffOptionsStore,
        repositoryWindow: RepositoryWindowController
    ) {
        self.store = store
        self.commands = commands
        self.diffOptions = diffOptions
        self.repositoryWindow = repositoryWindow
    }

    var records: [OpenWindows.ReviewWindow] {
        controllers.map(\.record)
    }

    var openReviews: Set<UUID> {
        Set(controllers.map(\.session.id))
    }

    func show(_ id: UUID, from sourceWindow: NSWindow?, repositoryName: String, frame: String? = nil) {
        if let existing = controllers.first(where: { $0.session.id == id }) {
            existing.showWindow(nil)
            return
        }
        guard store.review(id, in: commands.repository) != nil else { return }
        store.update(id, in: commands.repository) { $0.lastOpened = Date() }
        let key = id.uuidString.lowercased()
        let controller = ReviewWindowController(
            session: ReviewSession(id: id, store: store, commands: commands),
            place: places[key],
            repositoryName: repositoryName,
            diffOptions: diffOptions
        )
        controller.repositoryWindow = repositoryWindow
        controller.reviewCommands = reviewCommands
        controller.onRename = { [weak self, weak controller] in self?.rename?(id, controller?.window) }
        controller.onDelete = { [weak self, weak controller] in self?.delete?(id, controller?.window) }
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            places[key] = controller.place
            controllers.removeAll { $0 === controller }
            onChange?()
        }
        controller.onChange = { [weak self, weak controller] in
            guard let self, let controller else { return }
            places[key] = controller.place
            onChange?()
        }
        controllers.append(controller)
        if let window = controller.window {
            OpenedWindowPlacement.place(window, at: frame, cascadingFrom: sourceWindow)
        }
        controller.showWindow(nil)
        if let refs {
            controller.session.refresh(refs: refs, head: head)
        }
        onChange?()
    }

    /// After every refresh, so an open review keeps up with its branches and the working tree.
    func show(refs: [Ref], head: String?) {
        self.refs = refs
        self.head = head
        for controller in controllers {
            controller.session.refresh(refs: refs, head: head)
        }
    }

    func forget(_ id: UUID) {
        controllers.first { $0.session.id == id }?.close()
        places[id.uuidString.lowercased()] = nil
        onChange?()
    }

    func showRepositoryName(_ name: String) {
        for controller in controllers {
            controller.showRepositoryName(name)
        }
    }

    func closeAll() {
        for controller in controllers {
            places[controller.session.id.uuidString.lowercased()] = controller.place
            controller.close()
        }
        controllers.removeAll()
    }
}
