import AppKit
import SwiftUI

/// A repository window's commands for its remotes: fetching, pulling and pushing, the remotes
/// themselves, tags on them, and fetching by itself now and then. Their progress shows in a bar
/// above the history.
final class RemotesCoordinator {
    let sync: RemoteSyncWorkflow
    let editing: RemoteEditingWorkflow
    /// Goes above the history.
    let progressBar: NSView
    /// After a fetch or pull, which may have brought in commits.
    private var didFetch: (() -> Void)?
    /// Where an automatic fetch's failure shows, until one works.
    private var warning: BackgroundFailureWarning?

    private let tags: RemoteTagWorkflow
    private let runner: RemoteOperationRunner
    private let commands: RepositoryCommandRunner
    private let askpass: AskpassServer
    private var repositoryWindow: () -> NSWindow? = { nil }
    private lazy var automaticFetch = AutomaticFetch(preferences: preferences) { [weak self] in
        await self?.fetchAutomatically()
    }
    private let preferences: FetchPreferences
    /// As of the last refresh.
    private var contents: SidebarContents?

    init(
        commands: RepositoryCommandRunner,
        queue: WorkingAreaCommandQueue,
        askpass: AskpassServer,
        preferences: FetchPreferences
    ) {
        self.commands = commands
        self.askpass = askpass
        self.preferences = preferences
        runner = RemoteOperationRunner(commands: commands, askpass: askpass)
        sync = RemoteSyncWorkflow(runner: runner, commands: commands, queue: queue)
        editing = RemoteEditingWorkflow(commands: commands, queue: queue, runner: runner, sync: sync)
        tags = RemoteTagWorkflow(runner: runner, queue: queue)
        let bar = NSHostingView(rootView: RemoteProgressBar(model: runner.progress))
        bar.sizingOptions = [.intrinsicContentSize]
        progressBar = bar
        sync.didFetch = { [weak self] in self?.didFetch?() }
        sync.fetchOptions = { [preferences] in preferences.options }
        sync.willStart = { [weak self] in self?.automaticFetch.cancelCurrent() }
    }

    /// Once the window exists: where a command acts from when it wasn't started from one of the
    /// repository's windows, where its failure shows, and where an automatic fetch's does.
    func connect(
        window: @escaping () -> NSWindow?,
        failureSheet: GitFailureSheetPresenter,
        warning: BackgroundFailureWarning,
        didFetch: @escaping () -> Void
    ) {
        repositoryWindow = window
        self.warning = warning
        self.didFetch = didFetch
        sync.repositoryWindow = window
        editing.repositoryWindow = window
        tags.repositoryWindow = window
        let repository = commands.repository
        // On the window the command was started from, while it's still open.
        let present = { (failure: GitFailure, source: NSWindow?, retry: (() -> Void)?, nextSteps: GitFailureNextSteps) in
            guard let target = source?.isVisible == true ? source : window() else { return }
            failureSheet.present(failure, repository: repository, on: target, wasOpenedByUser: false, retry: retry, nextSteps: nextSteps)
        }
        sync.present = present
        tags.present = present
    }

    func start() {
        automaticFetch.start()
    }

    func makeFetchOptionsMenu() -> NSMenu {
        preferences.makeOptionsMenu()
    }

    func stop() {
        automaticFetch.stop()
        runner.cancel()
    }

    /// After each refresh.
    func show(branch: RepositoryStatus.Branch, contents: SidebarContents) {
        self.contents = contents
        let remotes = contents.remotes.map(\.name)
        let checkedOut = contents.branches.first(where: \.isCheckedOut)
        sync.state = RemoteState(branch: branch, isUpstreamGone: checkedOut?.isUpstreamGone ?? false, remotes: remotes)
        editing.remotes = remotes
    }

    /// The sidebar's remote and tag commands reach the workflows from anywhere in the window.
    func target(forAction action: Selector) -> Any? {
        if RemoteSyncWorkflow.actions.contains(action) {
            return sync
        }
        if RemoteEditingWorkflow.actions.contains(action) {
            return editing
        }
        return nil
    }

    /// From a remote's or tag's context menu in the sidebar.
    func perform(_ command: AppCommand, on id: SidebarItemID) {
        let window = actingWindow
        switch (command, id) {
        case let (.fetchFromRemote, .remote(name)):
            sync.fetch(name, from: window)
        case let (.editRemote, .remote(name)):
            editing.edit(name, from: window)
        case let (.removeRemote, .remote(name)):
            editing.remove(name, from: window)
        case (.pushTag, .ref), (.deleteRemoteTag, .ref):
            guard let tag = tagName(id) else { return }
            Task { [weak self] in
                guard let self, let remote = await remote(for: command, tag: tag, from: window) else { return }
                if command == .pushTag {
                    tags.push(tag, to: remote, from: window)
                } else {
                    tags.delete(tag, from: remote, window: window)
                }
            }
        default:
            break
        }
    }

    /// The remotes or tags a remote command in the palette offers: only the one selected in the
    /// sidebar when it's one, and otherwise all of them.
    func paletteChoices(for command: AppCommand, selection: SidebarItemID?) -> [CommandPaletteDestination]? {
        switch command {
        case .fetchFromRemote:
            return remoteChoices(selection: selection) { [weak self] name in
                self?.sync.fetch(name, from: self?.actingWindow)
            }
        case .editRemote:
            return remoteChoices(selection: selection) { [weak self] name in
                self?.editing.edit(name, from: self?.actingWindow)
            }
        case .removeRemote:
            return remoteChoices(selection: selection) { [weak self] name in
                self?.editing.remove(name, from: self?.actingWindow)
            }
        case .pushTag:
            return tagChoices(selection: selection, placeholder: "Push to Remote") { [weak self] tag, remote in
                self?.tags.push(tag, to: remote, from: self?.actingWindow)
            }
        case .deleteRemoteTag:
            return tagChoices(selection: selection, placeholder: "Delete from Remote") { [weak self] tag, remote in
                self?.tags.delete(tag, from: remote, window: self?.actingWindow)
            }
        default:
            return nil
        }
    }

    private func remoteChoices(selection: SidebarItemID?, act: @escaping (String) -> Void) -> [CommandPaletteDestination] {
        guard !runner.isBusy, let contents else { return [] }
        let selected = contents.remotes.first { remote in
            remote.id == selection || remote.branches.contains { $0.id == selection }
        }
        return (selected.map { [$0] } ?? contents.remotes).map { remote in
            CommandPaletteDestination(id: "remote:\(remote.name)", kind: .remote, title: remote.name) { act(remote.name) }
        }
    }

    private func tagChoices(
        selection: SidebarItemID?,
        placeholder: String,
        act: @escaping (_ tag: String, _ remote: String) -> Void
    ) -> [CommandPaletteDestination] {
        guard !runner.isBusy, let contents, !contents.remotes.isEmpty else { return [] }
        let selected = contents.tags.first { $0.id == selection }
        return (selected.map { [$0] } ?? contents.tags).map { tag in
            let remotes = contents.remotes.map { remote in
                CommandPaletteDestination(id: "remote:\(remote.name)", kind: .remote, title: remote.name) { act(tag.name, remote.name) }
            }
            return CommandPaletteDestination(
                id: "ref:refs/tags/\(tag.name)",
                kind: .tag,
                title: tag.name,
                next: CommandPaletteDestination.NextStep(placeholder: placeholder, choices: remotes)
            ) {
                // Choosing the remote in the next step is what acts.
            }
        }
    }

    /// The only remote, or the one the user picks.
    private func remote(for command: AppCommand, tag: String, from window: NSWindow?) async -> String? {
        guard let remotes = contents?.remotes.map(\.name), !remotes.isEmpty else { return nil }
        if remotes.count == 1 {
            return remotes.first
        }
        let isPush = command == .pushTag
        return await RemoteChoiceAlert.ask(
            isPush ? "Push the tag “\(tag)” to which remote?" : "Delete the tag “\(tag)” from which remote?",
            informativeText: isPush ? "The tag goes to the remote as it is in this repository." : "The tag stays in this repository.",
            remotes: remotes,
            confirmTitle: isPush ? "Push" : "Continue",
            on: window
        )
    }

    private func tagName(_ id: SidebarItemID) -> String? {
        guard case let .ref(name) = id, name.hasPrefix("refs/tags/") else { return nil }
        return String(name.dropFirst("refs/tags/".count))
    }

    /// The palette gives focus back to the window it was opened over before a command runs.
    private var actingWindow: NSWindow? {
        NSApp.keyWindow ?? repositoryWindow()
    }

    /// Declines every question, since nobody asked for this fetch and a sheet out of nowhere would
    /// interrupt them.
    private func fetchAutomatically() async {
        guard !runner.isBusy, !sync.state.remotes.isEmpty else { return }
        var command = RemoteCommand.automaticFetch(prunes: preferences.options.prunes)
        command.askpass = askpass.open { _ in nil }
        defer { askpass.close(command.askpass) }
        guard let result = try? await commands.run(command), !Task.isCancelled else { return }
        if result.status == 0 {
            warning?.clear(.automaticFetch)
            didFetch?()
        } else {
            let failure = GitFailure(summary: "Git couldn’t fetch in the background.", arguments: command.arguments, result: result)
            warning?.report(failure, from: .automaticFetch)
        }
    }
}
