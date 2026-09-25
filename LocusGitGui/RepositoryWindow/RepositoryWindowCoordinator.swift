import AppKit
import os

/// Keeps one window per repository. Opening a repository that is already open brings its window
/// forward instead of opening a second.
final class RepositoryWindowCoordinator {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "RepositoryWindow")

    private let gitChoice: GitChoiceStore
    private let logs: GitCommandLogs
    private let recents: RecentRepositoryStore
    private let viewStates: RepositoryViewStateStore
    private let checkForMissingGit: () -> Void
    private let lastWindowClosed: () -> Void
    private var controllers: [String: RepositoryWindowController] = [:]

    init(
        gitChoice: GitChoiceStore,
        logs: GitCommandLogs,
        recents: RecentRepositoryStore,
        viewStates: RepositoryViewStateStore,
        checkForMissingGit: @escaping () -> Void,
        lastWindowClosed: @escaping () -> Void
    ) {
        self.gitChoice = gitChoice
        self.logs = logs
        self.recents = recents
        self.viewStates = viewStates
        self.checkForMissingGit = checkForMissingGit
        self.lastWindowClosed = lastWindowClosed
    }

    var hasOpenWindows: Bool {
        !controllers.isEmpty
    }

    func isRepositoryWindow(_ window: NSWindow) -> Bool {
        controllers.values.contains { $0.window === window }
    }

    /// A repository opened from the dashboard after File > New Tab joins the tabs of the window
    /// that was in front. Any other opens a window of its own, which macOS may still make a tab,
    /// following "Prefer tabs when opening documents" in System Settings.
    func show(_ repository: Repository, inTabsOf host: NSWindow? = nil) {
        if let existing = controllers[repository.id] {
            existing.showWindow(nil)
            return
        }
        let controller = makeController(for: repository)
        guard let window = controller.window else { return }
        if let host, host.isVisible {
            // After the last tab rather than the one in front, so several opened at once keep the
            // order they were chosen in.
            (host.tabGroup?.windows.last ?? host).addTabbedWindow(window, ordered: .above)
        } else if !controller.moveToRememberedFrame() {
            if let front = NSApp.orderedWindows.first(where: isRepositoryWindow) {
                let topLeft = window.cascadeTopLeft(from: NSPoint(x: front.frame.minX, y: front.frame.maxY))
                window.cascadeTopLeft(from: topLeft)
            } else {
                window.center()
            }
        }
        controller.showWindow(nil)
    }

    /// macOS brings back the window's frame, screen and tab group itself once it has the window.
    /// A repository that's gone since the last launch is left closed.
    func restore(_ repository: Repository, completionHandler: @escaping (NSWindow?, (any Error)?) -> Void) {
        Task {
            let presence = await RepositoryPresence.checkInBackground(repository)
            guard presence == .present, controllers[repository.id] == nil else {
                Self.log.info("Left a repository window closed at launch: \(String(describing: presence), privacy: .public)")
                completionHandler(nil, CocoaError(.fileNoSuchFile))
                return
            }
            completionHandler(makeController(for: repository).window, nil)
        }
    }

    private func makeController(for repository: Repository) -> RepositoryWindowController {
        let controller = RepositoryWindowController(
            commands: RepositoryCommandRunner(
                repository: repository,
                log: logs.log(for: repository),
                gitChoice: gitChoice,
                checkForMissingGit: checkForMissingGit
            ),
            displayName: recents.entries.first { $0.id == repository.id }?.displayName,
            viewStates: viewStates
        )
        controller.onDisplayNameRead = { [weak self] displayName in
            self?.recents.setDisplayName(displayName, for: repository)
            self?.retitleTabs()
        }
        controllers[repository.id] = controller
        retitleTabs()

        if let window = controller.window {
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: NSWindow.willCloseNotification, object: window) {
                    guard let self else { break }
                    controllers[repository.id] = nil
                    retitleTabs()
                    if controllers.isEmpty {
                        lastWindowClosed()
                    }
                    break
                }
            }
        }
        return controller
    }

    /// Only repositories without a display name are compared by folder name, since the rest are
    /// already told apart by the names they were given.
    private func retitleTabs() {
        let unnamed = controllers.values.filter { $0.displayName == nil }
        let folderNames = Dictionary(uniqueKeysWithValues: zip(
            unnamed.map(\.repository.id),
            DistinctFolderNames.make(for: unnamed.map(\.repository.workTree))
        ))
        for controller in controllers.values {
            controller.showTabTitle(controller.displayName ?? folderNames[controller.repository.id] ?? "")
        }
    }
}
