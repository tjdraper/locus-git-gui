import AppKit

/// Opens folders as repositories, from File > Open, the recent list, the Dock, Finder or `open -a`,
/// and explains the ones that aren't. Each repository it opens goes to the top of the recent list.
final class RepositoryOpeningWorkflow {
    private enum Outcome {
        case resolved(RepositoryResolution)
        case gitCouldNotStart
    }

    private let gitChoice: GitChoiceStore
    private let windows: RepositoryWindowCoordinator
    private let recents: RecentRepositoryStore
    private let didOpenRepository: () -> Void
    private let showChecklist: () -> Void
    private let checkForMissingGit: () -> Void
    /// Folders asked for before a usable Git was chosen, opened once one is.
    private var waitingForGit: [URL] = []
    private var openPanel: NSOpenPanel?

    init(
        gitChoice: GitChoiceStore,
        windows: RepositoryWindowCoordinator,
        recents: RecentRepositoryStore,
        didOpenRepository: @escaping () -> Void,
        showChecklist: @escaping () -> Void,
        checkForMissingGit: @escaping () -> Void
    ) {
        self.gitChoice = gitChoice
        self.windows = windows
        self.recents = recents
        self.didOpenRepository = didOpenRepository
        self.showChecklist = showChecklist
        self.checkForMissingGit = checkForMissingGit
    }

    func showOpenPanel() {
        NSApp.activate()
        if let openPanel {
            openPanel.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSOpenPanel()
        panel.message = "Choose a Git repository folder"
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        openPanel = panel
        panel.begin { [weak self] response in
            self?.openPanel = nil
            guard response == .OK else { return }
            self?.open(panel.urls)
        }
    }

    /// A repository found in place of a missing one on the recent list takes its place there.
    func open(_ folders: [URL], replacing missing: Repository? = nil, inTabsOf host: NSWindow? = nil) {
        Task {
            await openNow(folders, replacing: missing, inTabsOf: host)
        }
    }

    func openFoldersWaitingForGit() {
        let folders = waitingForGit
        waitingForGit = []
        if !folders.isEmpty {
            open(folders)
        }
    }

    private func openNow(_ folders: [URL], replacing missing: Repository?, inTabsOf host: NSWindow?) async {
        guard let runner = await gitChoice.runner() else {
            waitingForGit += folders
            showChecklist()
            return
        }

        var problems: [OpeningReport.Folder] = []
        var gitWentMissing = false
        for (folder, outcome) in await resolveAll(folders, with: runner) {
            switch outcome {
            case let .resolved(.repository(repository)):
                show(repository, replacing: missing, inTabsOf: host)
            case .resolved(.bare):
                problems.append(.init(url: folder, problem: .bare))
            case .resolved(.notRepository):
                problems.append(.init(url: folder, problem: .notRepository))
            case .resolved(.accessDenied):
                problems.append(.init(url: folder, problem: .accessDenied))
            case let .resolved(.failed(output)):
                problems.append(.init(url: folder, problem: .failed(output)))
            case .gitCouldNotStart:
                waitingForGit.append(folder)
                gitWentMissing = true
            }
        }

        if gitWentMissing {
            checkForMissingGit()
        }
        if let report = OpeningReport(folders: problems) {
            present(report)
        }
    }

    private func show(_ repository: Repository, replacing missing: Repository?, inTabsOf host: NSWindow?) {
        // A repository that arrived another way, such as a drop on the Dock icon, answers what the
        // panel was asking.
        openPanel?.cancel(nil)
        if let missing {
            recents.remove([missing])
        }
        recents.note(repository)
        didOpenRepository()
        windows.show(repository, inTabsOf: host)
    }

    /// Resolved side by side, and reported in the order they were given.
    private func resolveAll(_ folders: [URL], with runner: GitRunner) async -> [(URL, Outcome)] {
        await withTaskGroup(of: (Int, Outcome).self) { group in
            for (index, folder) in folders.enumerated() {
                group.addTask { (index, await Self.resolve(folder, with: runner)) }
            }
            var outcomes: [Int: Outcome] = [:]
            for await (index, outcome) in group {
                outcomes[index] = outcome
            }
            return folders.enumerated().compactMap { index, folder in
                outcomes[index].map { (folder, $0) }
            }
        }
    }

    private nonisolated static func resolve(_ folder: URL, with runner: GitRunner) async -> Outcome {
        // `open -a` can hand over a file, which opens the repository it is in.
        let isFolder = (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? true
        let directory = isFolder ? folder : folder.deletingLastPathComponent()
        do {
            return .resolved(try await RepositoryResolver.resolve(directory, with: runner))
        } catch ChildProcess.Failure.couldNotStart(let error) {
            return await couldNotStart(in: directory, because: error, runner: runner)
        } catch {
            return .resolved(.failed(error.localizedDescription))
        }
    }

    /// Starting Git in a folder fails for the folder's reasons as well as Git's: it was deleted,
    /// or macOS privacy protection refused to let the process into it.
    private nonisolated static func couldNotStart(in directory: URL, because error: any Error, runner: GitRunner) async -> Outcome {
        guard await GitInstallation.isUsable(runner.executableURL, environment: runner.environment) else {
            return .gitCouldNotStart
        }
        let posixCode = (error as NSError).domain == NSPOSIXErrorDomain ? Int32((error as NSError).code) : nil
        if posixCode == EPERM || posixCode == EACCES {
            return .resolved(.accessDenied)
        }
        if !FileManager.default.fileExists(atPath: directory.path) {
            return .resolved(.failed("The folder no longer exists."))
        }
        return .resolved(.failed(error.localizedDescription))
    }

    private func present(_ report: OpeningReport) {
        let alert = NSAlert()
        alert.messageText = report.messageText
        alert.informativeText = report.informativeText
        alert.alertStyle = .warning
        if report.offersPrivacySettings {
            alert.addButton(withTitle: "Open Privacy & Security")
            alert.addButton(withTitle: "OK")
        }
        NSApp.activate()
        let response = alert.runModal()
        if report.offersPrivacySettings, response == .alertFirstButtonReturn {
            PrivacySettings.openFilesAndFolders()
        }
    }
}
