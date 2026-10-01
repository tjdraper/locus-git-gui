import AppKit
import os
import SwiftUI

/// A repository's reviews: the list in the toolbar's popover and in a window of its own, the review
/// windows, and keeping every recent review up to date as the repository changes.
final class ReviewsCoordinator {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "Reviews")

    let windows: ReviewWindowCoordinator
    let list: ReviewList
    private let store: ReviewStore
    private let commands: RepositoryCommandRunner
    private var repositoryName: String
    private var listWindow: NSWindow?
    private var popover: NSPopover?
    private var refs: [Ref]?
    private var head: String?
    private var following: Task<Void, Never>?
    private(set) lazy var commandTarget = ReviewCommands(
        newReview: { [weak self] window in self?.newReview(from: window) },
        showReviews: { [weak self] window, item in self?.showList(from: window, relativeTo: item) }
    )
    /// When the list's window opens or closes, a review window changes, or Show Older Reviews is
    /// turned on or off, for the repository to remember.
    var onChange: (() -> Void)?

    init(
        commands: RepositoryCommandRunner,
        diffOptions: DiffOptionsStore,
        repositoryName: String,
        repositoryWindow: RepositoryWindowController,
        store: ReviewStore = .shared
    ) {
        self.store = store
        self.commands = commands
        self.repositoryName = repositoryName
        store.load(commands.repository)
        windows = ReviewWindowCoordinator(
            store: store,
            commands: commands,
            diffOptions: diffOptions,
            repositoryWindow: repositoryWindow
        )
        list = ReviewList(repository: commands.repository, store: store)
        windows.onChange = { [weak self] in self?.onChange?() }
        list.onChange = { [weak self] in self?.onChange?() }
        list.onOpen = { [weak self] id in self?.open(id, from: NSApp.keyWindow) }
        list.onNewReview = { [weak self] in self?.newReview(from: NSApp.keyWindow) }
        list.onRename = { [weak self] id in self?.rename(id, on: NSApp.keyWindow) }
        list.onDelete = { [weak self] id in self?.delete(id, on: NSApp.keyWindow) }
        windows.rename = { [weak self] id, window in self?.rename(id, on: window) }
        windows.delete = { [weak self] id, window in self?.delete(id, on: window) }
        windows.reviewCommands = commandTarget
    }

    var isListShown: Bool {
        listWindow?.isVisible == true
    }

    var places: [String: ReviewPlace] {
        windows.places
    }

    /// As the repository's window was last left, before anything is restored.
    func adopt(places: [String: ReviewPlace], showsOlder: Bool) {
        windows.places = places
        list.showsOlder = showsOlder
    }

    func open(_ id: UUID, from window: NSWindow?) {
        guard ReadOnlyLock.allowsChange(in: window) else { return }
        popover?.performClose(nil)
        windows.show(id, from: window, repositoryName: repositoryName)
    }

    /// Compares the checked-out branch with the branch it's most likely to merge into, both of
    /// which can be changed in the review's window.
    func newReview(from window: NSWindow?) {
        guard ReadOnlyLock.allowsChange(in: window) else { return }
        let review = Review(base: defaultBase(), head: defaultHead(), created: Date())
        store.add(review, in: commands.repository)
        open(review.id, from: window)
    }

    private func defaultHead() -> ReviewPoint {
        guard let checkedOut = refs?.first(where: { $0.isCheckedOut && $0.kind == .localBranch }) else { return .checkedOut }
        return .ref(checkedOut.name)
    }

    /// The remote's default branch, as `origin/HEAD` names it, or else a local `main` or `master`.
    private func defaultBase() -> ReviewPoint {
        let refs = refs ?? []
        if let target = refs.first(where: { $0.name == "refs/remotes/origin/HEAD" })?.symbolicTarget,
           refs.contains(where: { $0.name == target }) {
            return .ref(target)
        }
        for name in ["refs/heads/main", "refs/heads/master"] where refs.contains(where: { $0.name == name }) {
            return .ref(name)
        }
        return .checkedOut
    }

    func rename(_ id: UUID, on window: NSWindow?) {
        guard let review = store.review(id, in: commands.repository), let window = window ?? NSApp.keyWindow else { return }
        guard ReadOnlyLock.allowsChange(in: window) else { return }
        Task {
            let name = await FormSheet.ask(on: window) { finish in
                ReviewNameForm(name: review.name ?? "", placeholder: review.comparison, finish: finish)
            }
            guard let name else { return }
            store.update(id, in: commands.repository) { review in
                review.name = name.isEmpty ? nil : name
                review.lastChanged = Date()
            }
        }
    }

    func delete(_ id: UUID, on window: NSWindow?) {
        guard let review = store.review(id, in: commands.repository) else { return }
        guard ReadOnlyLock.allowsChange(in: window) else { return }
        Task {
            let confirmed = await Confirmation.ask(
                "Delete the review “\(review.title)”?",
                informativeText: "Its checks and comments are deleted with it. The repository and its branches aren’t changed.",
                confirmTitle: "Delete",
                on: window
            )
            guard confirmed else { return }
            windows.forget(id)
            store.delete(id, in: commands.repository)
            do {
                _ = try await commands.run(ReviewKeptObjects.deleteCommand(for: id))
            } catch {
                Self.log.error("Deleting a review's kept files failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    /// From the toolbar's button, as a popover under it, or as a window when the button isn't there.
    func showList(from window: NSWindow?, relativeTo item: NSToolbarItem?) {
        guard ReadOnlyLock.allowsChange(in: window) else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let item = item ?? window?.toolbar?.items.first { $0.itemIdentifier == AppCommand.showReviews.toolbarIdentifier }
        guard let item, item.view?.window != nil || window?.toolbar?.isVisible == true else {
            showListWindow()
            return
        }
        let popover = popover ?? makePopover()
        self.popover = popover
        popover.show(relativeTo: item)
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        let content = NSHostingController(rootView: ReviewListView(list: list) { [weak self] in
            self?.popover?.performClose(nil)
            self?.showListWindow()
        }
        .frame(width: 380, height: 420))
        popover.contentViewController = content
        return popover
    }

    func showListWindow() {
        let window = listWindow ?? makeListWindow()
        listWindow = window
        window.makeKeyAndOrderFront(nil)
        onChange?()
    }

    private func makeListWindow() -> NSWindow {
        let content = NSHostingController(rootView: ReviewListView(list: list))
        // The list fills whatever size the window is given.
        content.sizingOptions = []
        let window = NSWindow(contentViewController: content)
        window.contentMinSize = NSSize(width: 320, height: 240)
        window.title = "Reviews"
        window.subtitle = repositoryName
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Gives the title bar room for the subtitle.
        window.toolbar = NSToolbar(identifier: "ReviewListWindow")
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        RememberedWindowPlacement(autosaveName: "Reviews").apply(to: window, initialContentSize: NSSize(width: 440, height: 520))
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSWindow.willCloseNotification, object: window) {
                // Still visible while it closes.
                DispatchQueue.main.async { self?.onChange?() }
            }
        }
        return window
    }

    func showRepositoryName(_ name: String) {
        repositoryName = name
        listWindow?.subtitle = name
        windows.showRepositoryName(name)
    }

    /// After every refresh. Open reviews read their files again, and the rest opened recently follow
    /// their branches, so the list says when one has moved. Nothing is followed while the app is
    /// read-only.
    func show(refs: [Ref], head: String?) {
        self.refs = refs
        self.head = head
        guard !ReadOnlyLock.isLocked else { return }
        windows.show(refs: refs, head: head)
        following?.cancel()
        let open = windows.openReviews
        let recent = ReviewListing.shown(store.reviews(in: commands.repository), at: Date(), includingOlder: false)
            .map(\.id)
            .filter { !open.contains($0) }
        following = Task { [weak self, store, commands] in
            for id in recent {
                guard !Task.isCancelled else { return }
                do {
                    _ = try await ReviewRefresh.run(id, store: store, refs: refs, head: head, commands: commands, onlyWhenMoved: true)
                } catch is CancellationError {
                    return
                } catch {
                    Self.log.error("Following a review failed: \(String(describing: type(of: error)), privacy: .public)")
                }
            }
            self?.following = nil
        }
    }

    func restore(_ records: [OpenWindows.ReviewWindow], isListShown: Bool, from window: NSWindow?) {
        guard !ReadOnlyLock.isLocked else { return }
        for record in records {
            windows.show(record.review, from: window, repositoryName: repositoryName, frame: record.frame)
        }
        if isListShown {
            showListWindow()
        }
    }

    func closeAll() {
        following?.cancel()
        popover?.performClose(nil)
        listWindow?.close()
        windows.closeAll()
    }
}
