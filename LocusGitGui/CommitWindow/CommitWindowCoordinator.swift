import AppKit
import os

/// The commit windows opened from one repository's window. One window per commit: opening a
/// commit that's already open brings its window forward. They close with the repository's window.
final class CommitWindowCoordinator {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "CommitWindow")

    var reveal: ((SidebarItemID) -> Void)?
    var openFileWindow: ((FileWindowRequest, NSWindow?) -> Void)?
    /// When a window opens, closes, moves or shows another commit.
    var onChange: (() -> Void)?
    private let commands: RepositoryCommandRunner
    private let diffOptions: DiffOptionsStore
    private let diffPlaces: DiffPlaceStore
    private var controllers: [CommitWindowController] = []
    private var labels: [String: [CommitRefLabel]] = [:]
    private weak var repositoryWindow: RepositoryWindowController?

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

    /// Where it was left when `frame` says, and otherwise cascaded from the one in front.
    func show(_ commit: Commit, from repositoryWindow: NSWindow?, repositoryName: String, frame: String? = nil) {
        if let existing = controller(showing: commit.hash) {
            existing.showWindow(nil)
            return
        }
        let controller = CommitWindowController(
            repositoryName: repositoryName,
            commands: commands,
            diffOptions: diffOptions,
            diffPlaces: diffPlaces
        )
        controller.repositoryWindow = self.repositoryWindow
        controller.detail.messageFormat = self.repositoryWindow?.messageFormat
        controller.detail.reveal = { [weak self] item in self?.reveal?(item) }
        controller.detail.openFileWindow = { [weak self, weak controller] request in
            self?.openFileWindow?(request, controller?.window)
        }
        controller.detail.goToCommit = { [weak self, weak controller] hash in
            guard let controller else { return }
            self?.goToParent(hash, in: controller)
        }
        controller.onClose = { [weak self, weak controller] in
            self?.controllers.removeAll { $0 === controller }
            self?.onChange?()
        }
        controller.show(commit, labels: labels[commit.hash] ?? [])
        controllers.append(controller)
        if let window = controller.window {
            OpenedWindowPlacement.place(window, at: frame, cascadingFrom: controllers.dropLast().last?.window ?? repositoryWindow)
        }
        controller.showWindow(nil)
        controller.onChange = { [weak self] in self?.onChange?() }
        onChange?()
    }

    var records: [OpenWindows.CommitWindow] {
        controllers.compactMap { controller in
            controller.commit.map { OpenWindows.CommitWindow(commit: $0.hash, frame: controller.window?.frameDescriptor) }
        }
    }

    func showRepositoryName(_ name: String) {
        for controller in controllers {
            controller.showRepositoryName(name)
        }
    }

    /// Kept up to date as refreshes move branches and tags.
    func showLabels(_ labels: [String: [CommitRefLabel]]) {
        self.labels = labels
        for controller in controllers {
            guard let hash = controller.commit?.hash else { continue }
            controller.detail.showLabels(labels[hash] ?? [])
        }
    }

    func closeAll() {
        for controller in controllers {
            controller.close()
        }
        controllers.removeAll()
    }

    private func controller(showing hash: String) -> CommitWindowController? {
        controllers.first { $0.commit?.hash == hash }
    }

    /// A parent shows in the window it was clicked in, which is what the user is reading, unless
    /// it already has a window of its own.
    private func goToParent(_ hash: String, in controller: CommitWindowController) {
        if let existing = self.controller(showing: hash) {
            existing.showWindow(nil)
            return
        }
        Task { [weak self, weak controller, commands] in
            do {
                guard let commit = try await HistoryReader.readHashMatch(hash, running: commands.run) else {
                    NSSound.beep()
                    return
                }
                guard let self, let controller else { return }
                controller.show(commit, labels: labels[hash] ?? [])
            } catch {
                Self.log.error("Reading a parent failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }
}
