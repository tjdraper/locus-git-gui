import AppKit
import SwiftUI

/// Sets a repository's display name from a sheet, writes it to the repository, and shows it on the
/// recent list.
final class DisplayNameWorkflow {
    private let recents: RecentRepositoryStore
    private let gitChoice: GitChoiceStore
    private let logs: GitCommandLogs
    private let checkForMissingGit: () -> Void

    init(recents: RecentRepositoryStore, gitChoice: GitChoiceStore, logs: GitCommandLogs, checkForMissingGit: @escaping () -> Void) {
        self.recents = recents
        self.gitChoice = gitChoice
        self.logs = logs
        self.checkForMissingGit = checkForMissingGit
    }

    func edit(_ repository: Repository, over window: NSWindow) {
        Task {
            let current = await Self.read(from: repository.workTree)
            let isTracked = await isTracked(repository)
            present(current: current, isTracked: isTracked, for: repository, over: window)
        }
    }

    private func present(current: RepositoryDisplayName, isTracked: Bool, for repository: Repository, over window: NSWindow) {
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let close = { [weak window, weak sheet] in
            guard let window, let sheet else { return }
            window.endSheet(sheet)
        }
        sheet.contentViewController = NSHostingController(rootView: DisplayNameForm(
            folderName: repository.workTree.lastPathComponent,
            current: current,
            isTracked: isTracked,
            onSave: { [weak self] displayName in
                close()
                self?.save(displayName, to: repository, over: window)
            },
            onCancel: close
        ))
        window.beginSheet(sheet)
    }

    private func save(_ displayName: RepositoryDisplayName, to repository: Repository, over window: NSWindow) {
        Task {
            do {
                try await Self.write(displayName, to: repository.workTree)
                recents.setDisplayName(await Self.read(from: repository.workTree).name, for: repository)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "The display name couldn’t be saved"
                alert.informativeText = error.localizedDescription
                alert.beginSheetModal(for: window, completionHandler: nil)
            }
        }
    }

    /// When Git can't answer, the folder is taken as untracked, which only changes what the sheet
    /// offers.
    private func isTracked(_ repository: Repository) async -> Bool {
        let commands = RepositoryCommandRunner(
            repository: repository,
            log: logs.log(for: repository),
            gitChoice: gitChoice,
            checkForMissingGit: checkForMissingGit
        )
        guard let result = try? await commands.run(RepositoryDisplayName.trackedFilesCommand) else {
            return false
        }
        return RepositoryDisplayName.isTracked(result)
    }

    /// Off the main actor, since macOS may ask for permission to read the folder first, which
    /// blocks until the user answers.
    @concurrent
    private static func read(from workTree: URL) async -> RepositoryDisplayName {
        RepositoryDisplayName.read(from: workTree)
    }

    @concurrent
    private static func write(_ displayName: RepositoryDisplayName, to workTree: URL) async throws {
        try displayName.write(to: workTree)
    }
}
