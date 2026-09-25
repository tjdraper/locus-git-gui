import AppKit

/// Opens a repository chosen from the recent list. One that has moved or been deleted offers to
/// find it or take it off the list, as Finder does for an alias whose original is gone.
final class RecentRepositoryOpener {
    private let recents: RecentRepositoryStore
    private let opening: RepositoryOpeningWorkflow

    init(recents: RecentRepositoryStore, opening: RepositoryOpeningWorkflow) {
        self.recents = recents
        self.opening = opening
    }

    /// The dashboard knows a repository is missing when its folder is no longer a repository, which
    /// the menus can't tell without running Git.
    func open(_ repository: Repository, isMissing: Bool = false, over window: NSWindow? = nil) {
        if !isMissing, FileManager.default.fileExists(atPath: repository.workTree.path) {
            opening.open([repository.workTree])
            return
        }

        let alert = NSAlert()
        alert.messageText = "“\(repository.workTree.lastPathComponent)” can’t be found"
        alert.informativeText = """
        It may have been moved, renamed or deleted. It was at \
        \((repository.workTree.path as NSString).abbreviatingWithTildeInPath).
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Locate…")
        alert.addButton(withTitle: "Remove from List")
        alert.addButton(withTitle: "Cancel")
        let respond = { [weak self] (response: NSApplication.ModalResponse) in
            switch response {
            case .alertFirstButtonReturn:
                self?.locate(repository, over: window)
            case .alertSecondButtonReturn:
                self?.recents.remove(repository)
            default:
                break
            }
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: respond)
        } else {
            NSApp.activate()
            respond(alert.runModal())
        }
    }

    /// The repository found takes the missing one's place on the list.
    private func locate(_ repository: Repository, over window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.message = "Locate “\(repository.workTree.lastPathComponent)”"
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = Self.nearestExistingFolder(to: repository.workTree)
        let respond = { [weak self] (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            self?.opening.open([url], replacing: repository)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: respond)
        } else {
            NSApp.activate()
            panel.begin(completionHandler: respond)
        }
    }

    private static func nearestExistingFolder(to url: URL) -> URL {
        var folder = url.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }
}
