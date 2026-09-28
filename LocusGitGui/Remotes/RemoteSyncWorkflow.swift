import AppKit
import os

/// Fetch, Pull, Push and Force Push for the checked-out branch, from the Remote menu, the toolbar
/// and the palette. Pulls and pushes take their turn in the working area's queue, so a push made
/// straight after a commit waits for the commit.
final class RemoteSyncWorkflow: NSObject {
    static let actions: Set<Selector> = [
        #selector(fetch(_:)),
        #selector(fetchWithoutOptions(_:)),
        #selector(fetchAndPrune(_:)),
        #selector(fetchWithTags(_:)),
        #selector(pull(_:)),
        #selector(push(_:)),
        #selector(forcePush(_:)),
    ]

    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "Remotes")

    /// As of the last refresh.
    var state = RemoteState()
    /// Shows a failed command's sheet on the window it was started from.
    var present: ((GitFailure, NSWindow?, _ retry: (() -> Void)?, GitFailureNextSteps) -> Void)?
    /// After a fetch or pull brought in commits, which the refresh shows and the commit-graph file
    /// gains a layer for.
    var didFetch: (() -> Void)?
    /// Before the user's own command, which an automatic fetch would only hold up.
    var willStart: (() -> Void)?
    /// The window a command acts from when it wasn't started from one of the repository's windows.
    var repositoryWindow: (() -> NSWindow?)?
    /// What Fetch, and Fetch from Remote…, add to `git fetch`, as set in the preferences.
    var fetchOptions: () -> FetchOptions = { FetchOptions() }

    private let runner: RemoteOperationRunner
    private let commands: RepositoryCommandRunner
    private let queue: WorkingAreaCommandQueue

    init(runner: RemoteOperationRunner, commands: RepositoryCommandRunner, queue: WorkingAreaCommandQueue) {
        self.runner = runner
        self.commands = commands
        self.queue = queue
    }

    @objc func fetch(_: Any?) {
        fetch(nil, from: sourceWindow)
    }

    /// These three do only what they say, whatever the preferences add to Fetch.
    @objc func fetchWithoutOptions(_: Any?) {
        fetch(nil, options: FetchOptions(), from: sourceWindow)
    }

    @objc func fetchAndPrune(_: Any?) {
        fetch(nil, options: .prune, from: sourceWindow)
    }

    @objc func fetchWithTags(_: Any?) {
        fetch(nil, options: .tags, from: sourceWindow)
    }

    @objc func pull(_: Any?) {
        pull(nil, from: sourceWindow)
    }

    @objc func push(_: Any?) {
        push(from: sourceWindow)
    }

    @objc func forcePush(_: Any?) {
        forcePush(from: sourceWindow)
    }

    /// Every remote when `remote` is nil, and with the preferences' options when `options` is.
    /// Runs beside staging and committing, which it can't disturb.
    func fetch(_ remote: String?, options: FetchOptions? = nil, from window: NSWindow?) {
        guard canFetch else {
            NSSound.beep()
            return
        }
        let named = remote ?? (state.remotes.count == 1 ? state.remotes.first : nil)
        let options = options ?? fetchOptions()
        start()
        Task { [weak self] in
            guard let self else { return }
            defer { runner.release() }
            let outcome = await runner.run(
                remote.map { RemoteCommand.fetch($0, options) } ?? RemoteCommand.fetchAll(options),
                titled: named.map { "Fetching from “\($0)”" } ?? "Fetching from all remotes",
                failureSummary: named.map { "Git couldn’t fetch from “\($0)”." } ?? "Git couldn’t fetch from every remote.",
                from: window
            )
            finish(outcome, from: window, fetched: true) { [weak self] in self?.fetch(remote, options: options, from: window) }
        }
    }

    func pull(_ strategy: RemoteCommand.PullStrategy?, from window: NSWindow?) {
        guard canPull, let branch = state.branch?.name, let upstream = state.branch?.upstream else {
            NSSound.beep()
            return
        }
        start()
        queue.run("") { [weak self] in
            guard let self else { return }
            defer { runner.release() }
            let outcome = await runner.run(
                RemoteCommand.pull(strategy),
                titled: "Pulling “\(upstream)” into “\(branch)”",
                failureSummary: "Git couldn’t pull “\(upstream)” into “\(branch)”.",
                from: window
            )
            if case let .failed(failure) = outcome, failure.recognized == .pullNeedsStrategy {
                // The pull fetched before it stopped.
                didFetch?()
                // Once this pull has released the runner, since the one chosen takes its place.
                Task { [weak self] in await self?.askPullStrategy(branch: branch, upstream: upstream, from: window) }
                return
            }
            finish(outcome, from: window, fetched: true) { [weak self] in self?.pull(strategy, from: window) }
        }
    }

    func push(from window: NSWindow?) {
        guard canPush, let branch = state.branch?.name else {
            NSSound.beep()
            return
        }
        guard state.branch?.upstream == nil else {
            enqueuePush(RemoteCommand.push, titled: "Pushing “\(branch)”", from: window)
            return
        }
        Task { [weak self] in
            guard let self, let remote = await remoteForFirstPush(of: branch, from: window) else { return }
            enqueuePush(
                RemoteCommand.pushSettingUpstream(branch: branch, to: remote),
                titled: "Pushing “\(branch)” to “\(remote)”",
                from: window
            )
        }
    }

    /// Asks first, naming how many commits the remote's branch has that this one doesn't, and the
    /// commit it's at, which can be pushed back to undo it.
    func forcePush(from window: NSWindow?) {
        guard canForcePush, let branch = state.branch?.name, let upstream = state.branch?.upstream else {
            NSSound.beep()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let replaced = await ForcePushConfirmation.readReplaced(running: commands.run)
            let isConfirmed = await ForcePushConfirmation.ask(
                branch: branch,
                upstream: upstream,
                replaced: replaced,
                on: window ?? repositoryWindow?()
            )
            guard isConfirmed else { return }
            enqueuePush(RemoteCommand.forcePush, titled: "Force pushing “\(branch)”", from: window) { [weak self] in
                guard let replaced else { return }
                self?.runner.progress.show(RemoteProgress.Notice(
                    message: "“\(upstream)” was at \(replaced.shortHash) before the force push. This repository still has it.",
                    hash: replaced.hash
                ))
            }
        }
    }

    private func enqueuePush(_ command: GitCommand, titled title: String, from window: NSWindow?, then succeeded: (() -> Void)? = nil) {
        // Checked again, since the user may have started something else while asked which remote.
        guard !runner.isBusy else {
            NSSound.beep()
            return
        }
        let branch = state.branch?.name ?? "the branch"
        start()
        queue.run("") { [weak self] in
            guard let self else { return }
            defer { runner.release() }
            let outcome = await runner.run(command, titled: title, failureSummary: "Git couldn’t push “\(branch)”.", from: window)
            if case .succeeded = outcome {
                succeeded?()
            }
            finish(outcome, from: window, fetched: false) { [weak self] in self?.push(from: window) }
        }
    }

    private func start() {
        willStart?()
        runner.reserve()
    }

    private func finish(_ outcome: RemoteOperationRunner.Outcome, from window: NSWindow?, fetched: Bool, retry: @escaping () -> Void) {
        switch outcome {
        case .succeeded:
            if fetched {
                didFetch?()
            }
        case let .failed(failure):
            Self.log.error("A remote command failed with status \(failure.result.status, privacy: .public)")
            present?(failure, window, retry, GitFailureNextSteps(
                pull: { [weak self] in self?.pull(nil, from: window) },
                push: { [weak self] in self?.push(from: window) },
                forcePush: { [weak self] in self?.forcePush(from: window) },
                fetch: { [weak self] in self?.fetch(nil, from: window) }
            ))
        case .stopped:
            break
        }
    }

    /// Asked once Git has said the branches diverged, and remembered in the repository's own
    /// configuration when the user says to.
    private func askPullStrategy(branch: String, upstream: String, from window: NSWindow?) async {
        guard let window = window ?? repositoryWindow?() else { return }
        let divergence = await PullStrategySheet.readDivergence(running: commands.run)
        guard let choice = await PullStrategySheet.ask(branch: branch, upstream: upstream, divergence: divergence, on: window) else {
            return
        }
        if choice.remember {
            queue.run("Git couldn’t save the choice in the repository’s configuration.") { [commands] in
                let command = RemoteCommand.rememberPullStrategy(choice.strategy)
                let result = try await commands.run(command)
                guard result.status == 0 else { throw WorkingAreaStaging.Failure(command: command, result: result) }
            }
        }
        pull(choice.strategy, from: window)
    }

    /// The remote a branch with no upstream is pushed to: the only one, the one the configuration
    /// names, or `origin`. With several and none of those, the user picks.
    private func remoteForFirstPush(of branch: String, from window: NSWindow?) async -> String? {
        let remotes = state.remotes
        if remotes.count == 1 {
            return remotes.first
        }
        for command in [RemoteCommand.pushRemote(of: branch), RemoteCommand.defaultPushRemote] {
            if let result = try? await commands.run(command), result.status == 0,
               let name = String(bytes: result.standardOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               remotes.contains(name) {
                return name
            }
        }
        if remotes.contains("origin") {
            return "origin"
        }
        return await RemoteChoiceAlert.ask(
            "Push “\(branch)” to which remote?",
            informativeText: "The branch doesn’t have an upstream yet. The push makes the remote’s branch of the same name its upstream.",
            remotes: remotes,
            confirmTitle: "Push",
            on: window ?? repositoryWindow?()
        )
    }

    /// One of the repository's windows, since the action reached here through its responder chain.
    private var sourceWindow: NSWindow? {
        NSApp.keyWindow ?? repositoryWindow?()
    }

    private var canFetch: Bool {
        !runner.isBusy && !state.remotes.isEmpty
    }

    private var canPull: Bool {
        guard let branch = state.branch else { return false }
        return !runner.isBusy && branch.name != nil && branch.upstream != nil && !state.isUpstreamGone
    }

    private var canPush: Bool {
        guard let branch = state.branch else { return false }
        return !runner.isBusy && branch.name != nil && branch.commit != nil && !state.remotes.isEmpty
    }

    private var canForcePush: Bool {
        canPush && state.branch?.upstream != nil && !state.isUpstreamGone
    }

    private func isEnabled(_ action: Selector?) -> Bool {
        switch action {
        case #selector(fetch(_:)), #selector(fetchWithoutOptions(_:)), #selector(fetchAndPrune(_:)), #selector(fetchWithTags(_:)): canFetch
        case #selector(pull(_:)): canPull
        case #selector(push(_:)): canPush
        case #selector(forcePush(_:)): canForcePush
        default: true
        }
    }
}

extension RemoteSyncWorkflow: NSMenuItemValidation, NSToolbarItemValidation {
    /// Fetch is named with what the preferences add to it, such as “Fetch (Prune, Tags)”.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(fetch(_:)) {
            menuItem.title = fetchOptions().fetchTitle
        }
        return isEnabled(menuItem.action)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.action == #selector(fetch(_:)) {
            let title = fetchOptions().fetchTitle
            item.toolTip = AppCommand.fetch.shortcut.map { "\(title) (\($0.displayText))" } ?? title
        }
        return isEnabled(item.action)
    }
}

/// What the remote commands need to know about the repository, as of the last refresh.
struct RemoteState {
    var branch: RepositoryStatus.Branch?
    /// The checked-out branch's upstream has been deleted from the remote.
    var isUpstreamGone = false
    var remotes: [String] = []
}
