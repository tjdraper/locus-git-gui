import AppKit

/// Opens repositories chosen from the recent list. One that has moved or been deleted offers to
/// find it or take it off the list, as Finder does for an alias whose original is gone.
final class RecentRepositoryOpener {
    private let recents: RecentRepositoryStore
    private let opening: RepositoryOpeningWorkflow

    init(recents: RecentRepositoryStore, opening: RepositoryOpeningWorkflow) {
        self.recents = recents
        self.opening = opening
    }

    /// The dashboard knows a repository is missing when its folder is no longer a repository, which
    /// the file system alone can't tell. The ones that are there open while the rest are asked about.
    func open(_ repositories: [Repository], knownMissing: Set<String> = [], over window: NSWindow? = nil) {
        Task {
            var present: [Repository] = []
            var unavailable: [(repository: Repository, presence: RepositoryPresence)] = []
            for repository in repositories {
                let presence = knownMissing.contains(repository.id)
                    ? .missing
                    : await RepositoryPresence.checkInBackground(repository)
                if presence == .present {
                    present.append(repository)
                } else {
                    unavailable.append((repository, presence))
                }
            }
            if !present.isEmpty {
                opening.open(present.map(\.workTree))
            }
            // Opening closes the dashboard, so the question can't be a sheet on it.
            ask(about: unavailable, over: present.isEmpty ? window : nil)
        }
    }

    private func ask(about unavailable: [(repository: Repository, presence: RepositoryPresence)], over window: NSWindow?) {
        guard let first = unavailable.first else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        let offersLocate = unavailable.count == 1 && first.presence == .missing
        if unavailable.count == 1 {
            let name = first.repository.workTree.lastPathComponent
            let path = (first.repository.workTree.path as NSString).abbreviatingWithTildeInPath
            if first.presence == .driveNotConnected {
                alert.messageText = "“\(name)” is on a drive that isn’t connected"
                alert.informativeText = "Connect the drive and open it again. It was at \(path)."
            } else {
                alert.messageText = "“\(name)” can’t be found"
                alert.informativeText = "It may have been moved, renamed or deleted. It was at \(path)."
            }
        } else {
            alert.messageText = "\(unavailable.count) repositories can’t be opened"
            alert.informativeText = unavailable.map { repository, presence in
                let name = repository.workTree.lastPathComponent
                return presence == .driveNotConnected
                    ? "“\(name)” is on a drive that isn’t connected."
                    : "“\(name)” may have been moved, renamed or deleted."
            }.joined(separator: "\n")
        }
        if offersLocate {
            alert.addButton(withTitle: "Locate…")
        }
        alert.addButton(withTitle: "Remove from List")
        alert.addButton(withTitle: "Cancel")

        let removeButton: NSApplication.ModalResponse = offersLocate ? .alertSecondButtonReturn : .alertFirstButtonReturn
        let respond = { [weak self] (response: NSApplication.ModalResponse) in
            if offersLocate, response == .alertFirstButtonReturn {
                self?.locate(first.repository, over: window)
            } else if response == removeButton {
                self?.recents.remove(unavailable.map(\.repository))
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
