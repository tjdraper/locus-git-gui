import AppKit
import os
import SwiftUI

/// One Clone Repository window. The clone runs in the chosen folder, with its progress in the window
/// and questions from Git or SSH as sheets on it. A clone that fails or is stopped leaves nothing
/// behind: the folder it made is removed, and only a folder it made.
final class CloneWindowController: NSWindowController, NSWindowDelegate {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "Clone")

    let session = CloneSession()
    private let progress = RemoteProgress()
    private let gitChoice: GitChoiceStore
    private let logs: GitCommandLogs
    private let askpass: AskpassServer
    private let checkForMissingGit: () -> Void
    private let didClone: (URL) -> Void
    private let failureSheet = GitFailureSheetPresenter()
    private var runner: RemoteOperationRunner?

    init(
        gitChoice: GitChoiceStore,
        logs: GitCommandLogs,
        askpass: AskpassServer,
        checkForMissingGit: @escaping () -> Void,
        didClone: @escaping (URL) -> Void
    ) {
        self.gitChoice = gitChoice
        self.logs = logs
        self.askpass = askpass
        self.checkForMissingGit = checkForMissingGit
        self.didClone = didClone
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Clone Repository"
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: CloneForm(
            session: session,
            progress: progress,
            chooseParentFolder: { [weak self] in self?.chooseParentFolder() },
            clone: { [weak self] in self?.clone() },
            close: { [weak window] in window?.performClose(nil) }
        ))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    var isCloning: Bool {
        progress.running != nil
    }

    /// A clone of something copied just before, such as from a hosting site, starts with its address.
    func fillAddressFromClipboard() {
        guard session.address.isEmpty, let text = NSPasteboard.general.string(forType: .string), RemoteURL.looksLikeRemote(text) else {
            return
        }
        session.address = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Closing the window stops a clone in progress, which then cleans up after itself.
    func windowWillClose(_: Notification) {
        runner?.cancel()
    }

    private func chooseParentFolder() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.message = "Choose the folder to clone the repository into"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = session.parentFolder
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.session.parentFolder = url
        }
    }

    private func clone() {
        guard session.canClone, !isCloning else {
            NSSound.beep()
            return
        }
        session.rememberParentFolder()
        let destination = session.destination
        let repository = Repository(workTree: destination, gitDirectory: destination.appending(path: ".git", directoryHint: .isDirectory))
        // The new repository's Activity then starts with the clone that made it.
        let runner = RemoteOperationRunner(
            commands: RepositoryCommandRunner(
                repository: repository,
                log: logs.log(for: repository),
                gitChoice: gitChoice,
                checkForMissingGit: checkForMissingGit,
                directory: session.parentFolder
            ),
            askpass: askpass,
            progress: progress
        )
        self.runner = runner
        let command = RemoteCommand.clone(session.trimmedAddress, into: session.folderName, includingSubmodules: session.includesSubmodules)
        let existed = FileManager.default.fileExists(atPath: destination.path)
        let name = session.folderName
        Task { [weak self] in
            let outcome = await runner.run(
                command,
                titled: "Cloning “\(name)”",
                failureSummary: "Git couldn’t clone “\(name)”.",
                from: self?.window
            )
            self?.runner = nil
            switch outcome {
            case .succeeded:
                Self.log.info("Cloned a repository")
                self?.window?.close()
                self?.didClone(destination)
            case let .failed(failure):
                Self.removeIfMade(destination, existed: existed)
                guard let self, let window, window.isVisible else { return }
                failureSheet.present(failure, repository: repository, on: window, wasOpenedByUser: false, retry: nil)
            case .stopped:
                Self.removeIfMade(destination, existed: existed)
            }
        }
    }

    /// Git removes what it made when it fails, but not always when it's stopped partway.
    private static func removeIfMade(_ destination: URL, existed: Bool) {
        guard !existed, FileManager.default.fileExists(atPath: destination.path) else { return }
        do {
            try FileManager.default.removeItem(at: destination)
        } catch {
            // The error's description names the folder, which the log never gets.
            log.error("Couldn't remove a partial clone: error \((error as NSError).code, privacy: .public)")
        }
    }
}
