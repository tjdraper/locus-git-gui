import AppKit
import os

/// The commit windows opened from one repository's window. One window per commit: opening a
/// commit that's already open brings its window forward. They close with the repository's window.
final class CommitWindowCoordinator {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "CommitWindow")

    var reveal: ((SidebarItemID) -> Void)?
    var openFileWindow: ((FileWindowRequest, NSWindow?) -> Void)?
    private let commands: RepositoryCommandRunner
    private let diffOptions: DiffOptionsStore
    private var controllers: [CommitWindowController] = []
    private var labels: [String: [CommitRefLabel]] = [:]

    init(commands: RepositoryCommandRunner, diffOptions: DiffOptionsStore) {
        self.commands = commands
        self.diffOptions = diffOptions
    }

    /// Cascaded from the repository's window, so it's clear which repository it came from.
    func show(_ commit: Commit, from repositoryWindow: NSWindow?, repositoryName: String) {
        if let existing = controller(showing: commit.hash) {
            existing.showWindow(nil)
            return
        }
        let controller = CommitWindowController(repositoryName: repositoryName, commands: commands, diffOptions: diffOptions)
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
        }
        controller.show(commit, labels: labels[commit.hash] ?? [])
        controllers.append(controller)
        if let window = controller.window {
            let front = controllers.dropLast().last?.window ?? repositoryWindow
            if let front {
                let topLeft = window.cascadeTopLeft(from: NSPoint(x: front.frame.minX, y: front.frame.maxY))
                window.cascadeTopLeft(from: topLeft)
            } else {
                window.center()
            }
        }
        controller.showWindow(nil)
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
