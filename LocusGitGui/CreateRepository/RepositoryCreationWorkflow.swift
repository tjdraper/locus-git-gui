import AppKit
import SwiftUI

/// Makes a new repository with `git init` in a folder the user picks or makes, then opens it. A
/// folder that's already a repository just opens, and one inside another repository is asked about,
/// since a repository inside another is usually a mistake.
final class RepositoryCreationWorkflow {
    private let gitChoice: GitChoiceStore
    private let logs: GitCommandLogs
    private let checkForMissingGit: () -> Void
    private let showChecklist: () -> Void
    private let open: (URL) -> Void
    private let failureSheet = GitFailureSheetPresenter()

    init(
        gitChoice: GitChoiceStore,
        logs: GitCommandLogs,
        checkForMissingGit: @escaping () -> Void,
        showChecklist: @escaping () -> Void,
        open: @escaping (URL) -> Void
    ) {
        self.gitChoice = gitChoice
        self.logs = logs
        self.checkForMissingGit = checkForMissingGit
        self.showChecklist = showChecklist
        self.open = open
    }

    func showPanel() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.message = "Choose or make the folder for the new repository"
        panel.prompt = "Create"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let folder = panel.url else { return }
            self?.create(in: folder)
        }
    }

    func create(in folder: URL) {
        Task {
            guard let runner = await gitChoice.runner() else {
                showChecklist()
                return
            }
            switch try? await RepositoryResolver.resolve(folder, with: runner) {
            case let .repository(existing) where ResolvedPath.of(existing.workTree).path == ResolvedPath.of(folder).path:
                open(folder)
                return
            case let .repository(existing):
                guard await confirmNested(folder, in: existing) else { return }
            case .bare:
                report("“\(folder.lastPathComponent)” is already a bare repository.")
                return
            case .accessDenied:
                report(
                    "Locus Git Gui isn’t allowed to read “\(folder.lastPathComponent)”.",
                    detail: "Allow access under Files & Folders in Privacy & Security settings, then try again."
                )
                return
            case .notRepository, .failed, nil:
                break
            }
            await initialize(folder)
        }
    }

    private func initialize(_ folder: URL) async {
        let repository = Repository(workTree: folder, gitDirectory: folder.appending(path: ".git", directoryHint: .isDirectory))
        let commands = RepositoryCommandRunner(
            repository: repository,
            log: logs.log(for: repository),
            gitChoice: gitChoice,
            checkForMissingGit: checkForMissingGit
        )
        let command = GitCommand.changing(["init"])
        let failure: GitFailure
        do {
            let result = try await commands.run(command)
            guard result.status != 0 else {
                open(folder)
                return
            }
            failure = GitFailure(
                summary: "Git couldn’t make a repository in “\(folder.lastPathComponent)”.",
                arguments: command.arguments,
                result: result
            )
        } catch let ChildProcess.Failure.couldNotStart(error) {
            failure = GitFailure(
                summary: "Git couldn’t start in “\(folder.lastPathComponent)”.",
                arguments: command.arguments,
                result: ChildProcess.Result(status: -1, standardOutput: Data(), standardError: Data(error.localizedDescription.utf8))
            )
        } catch {
            return
        }
        if let window = NSApp.keyWindow {
            failureSheet.present(failure, repository: repository, on: window, wasOpenedByUser: false, retry: nil)
        } else {
            report(failure.summary, detail: failure.output)
        }
    }

    private func confirmNested(_ folder: URL, in existing: Repository) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "“\(folder.lastPathComponent)” is inside the repository “\(existing.workTree.lastPathComponent)”"
        alert.informativeText = """
        A new repository here is separate from “\(existing.workTree.lastPathComponent)”, which then \
        sees the folder as untracked files rather than the files in it. Create it anyway?
        """
        alert.addButton(withTitle: "Create Repository")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return await AlertPresentation.run(alert, on: nil) == .alertFirstButtonReturn
    }

    private func report(_ message: String, detail: String = "") {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }
}
