import AppKit
import os
import SwiftUI

/// One review in a window of its own: its files on the left, each with a checkbox, and the picked
/// file's changes on the right.
final class ReviewWindowController: NSWindowController, NSWindowDelegate {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "Reviews")
    private static let contentSize = NSSize(width: 1200, height: 820)
    private static let listWidth: CGFloat = 300

    let session: ReviewSession
    var onClose: (() -> Void)?
    /// When the window moves, or shows another file or another part of one, for the repository
    /// to remember.
    var onChange: (() -> Void)?
    weak var repositoryWindow: RepositoryWindowController?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?
    /// New Review and Show Reviews, which reach the repository's reviews from here too.
    var reviewCommands: ReviewCommands?
    let diff: DiffViewController
    private let reader: ReviewFileReader
    private(set) lazy var threads = ReviewThreadInserts(session: session, diff: diff)
    private lazy var detail = ReviewDetailViewController(
        diff: diff,
        overview: ReviewOverviewView(
            session: session,
            openFile: { [weak self] path in self?.session.selection = path },
            copyComments: { [weak self] in self?.copyReviewComments(nil) }
        )
    )
    private let split = NSSplitViewController()
    private let failureSheet = GitFailureSheetPresenter()
    private var repositoryName: String
    private var reading: Task<Void, Never>?
    /// Where each file was scrolled to, by `scrollKey`.
    private var scrolls: [String: DiffScrollAnchor]
    /// The file shown, as it was read, to tell whether a refresh changed it.
    private(set) var shown: (entry: ReviewSession.Entry, sinceReviewed: Bool)?
    private(set) var isLocked = false

    init(session: ReviewSession, place: ReviewPlace?, repositoryName: String, diffOptions: DiffOptionsStore) {
        self.session = session
        self.repositoryName = repositoryName
        scrolls = place?.scrolls ?? [:]
        session.selection = place?.selection
        session.hidesChecked = place?.hidesChecked ?? false
        session.showsWholeDiff = place?.showsWholeDiff ?? []
        diff = DiffViewController(options: diffOptions, workTree: session.repository.workTree)
        reader = ReviewFileReader(session: session, options: diffOptions)
        diff.opensFileWindows = false
        diff.showsSummary = false
        diff.highlightsCurrentFile = false
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // Brought back with its repository's window, rather than on its own after a relaunch.
        window.isRestorable = false
        // Kept apart from repository windows, which would otherwise take it as a tab.
        window.tabbingIdentifier = "ReviewWindow"
        // Gives the title bar room for the subtitle.
        window.toolbar = NSToolbar(identifier: "ReviewWindow")
        window.toolbarStyle = .unified
        super.init(window: window)
        let listController = NSHostingController(rootView: ReviewSidebarView(session: session) { [weak self] isBase in
            self?.chooseCommit(isBase: isBase)
        })
        listController.sizingOptions = []
        let listItem = NSSplitViewItem(viewController: listController)
        listItem.minimumThickness = 220
        listItem.maximumThickness = 480
        listItem.canCollapse = false
        listItem.holdingPriority = .defaultLow + 10
        split.addSplitViewItem(listItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: detail))
        let hasPlacedList = UserDefaults.standard.object(forKey: "NSSplitView Subview Frames ReviewWindowList") != nil
        split.splitView.autosaveName = "ReviewWindowList"
        window.contentViewController = split
        window.setContentSize(Self.contentSize)
        if !hasPlacedList {
            split.splitView.setPosition(Self.listWidth, ofDividerAt: 0)
        }
        window.delegate = self
        connectSession()
        connectDiff(diffOptions)
        connectComments()
        followReview()
        followEntitlement()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    var record: OpenWindows.ReviewWindow {
        OpenWindows.ReviewWindow(review: session.id, frame: window?.frameDescriptor)
    }

    var place: ReviewPlace {
        rememberScroll()
        return ReviewPlace(
            selection: session.selection,
            hidesChecked: session.hidesChecked,
            scrolls: scrolls,
            showsWholeDiff: session.showsWholeDiff
        )
    }

    func showRepositoryName(_ name: String) {
        repositoryName = name
        showTitle()
    }

    private func connectSession() {
        session.onSelectionChange = { [weak self] _ in self?.showSelection() }
        session.onFilesChange = { [weak self] in self?.showSelection() }
        session.onPlaceChange = { [weak self] in self?.onChange?() }
    }

    private func connectDiff(_ diffOptions: DiffOptionsStore) {
        diff.showFailure = { [weak self] failure, retry in
            guard let self, let window else { return }
            failureSheet.present(failure, repository: session.repository, on: window, wasOpenedByUser: true, retry: retry)
        }
        diff.onPlaceChange = { [weak self] _ in
            self?.rememberScroll()
            self?.onChange?()
        }
        diff.fileActions = { [weak self] _ in self?.fileActions() ?? [] }
        diff.readFile = { [weak self] _ in
            guard let self, let shown else { throw CancellationError() }
            return try await reader.read(shown.entry, sinceReviewed: shown.sinceReviewed, limits: .oneFile)
        }
        diff.readImage = { [weak self] file, isNew in
            guard let self else { return nil }
            return try await reader.readImage(file, isNew: isNew)
        }
        diff.adjacentFiles = DiffViewController.AdjacentFiles(
            canGo: { [weak self] offset in self?.session.canMove(by: offset) ?? false },
            move: { [weak self] offset in
                if self?.session.move(by: offset) != true {
                    NSSound.beep()
                }
            }
        )
        diff.onTypedKey = { [weak self] key in
            guard key == " ", NSApp.currentEvent?.modifierFlags.contains(.shift) != true, let self else { return false }
            session.checkAndMoveOn()
            return true
        }
        diffOptions.observe(self) { [weak self] _ in self?.showSelection(force: true) }
    }

    /// A refresh that leaves the file's changes as they were only updates its header, whose
    /// checkbox may have changed. `force` reads them again anyway, as with other diff options.
    func showSelection(force: Bool = false) {
        guard !isLocked else { return }
        detail.showsOverview = session.selection == ReviewSession.overviewTag
        guard let entry = session.selectedEntry else {
            reading?.cancel()
            rememberScroll()
            shown = nil
            threads.show([:], in: nil)
            diff.show([], emptyMessage: session.listing == nil ? "" : "No file is selected.", isSameDiff: false)
            return
        }
        let sinceReviewed = showsChangesSince(entry)
        let isSameView = shown?.entry.file.path == entry.file.path && shown?.sinceReviewed == sinceReviewed
        if isSameView, shown?.entry.file == entry.file, !force {
            if shown?.entry != entry {
                shown = (entry, sinceReviewed)
                diff.show(diff.files, emptyMessage: "", isSameDiff: true)
            }
            return
        }
        if !isSameView {
            rememberScroll()
            var placeholder = DiffFile(changed: entry.file, patch: FilePatch())
            placeholder.reading = .reading
            let scroll = scrolls[Self.scrollKey(entry.file.path, sinceReviewed: sinceReviewed)]
            diff.show([placeholder], emptyMessage: "", isSameDiff: false, place: DiffPlace(scroll: scroll))
        }
        shown = (entry, sinceReviewed)
        read(entry, sinceReviewed: sinceReviewed, isSameDiff: true)
    }

    private func read(_ entry: ReviewSession.Entry, sinceReviewed: Bool, isSameDiff: Bool) {
        reading?.cancel()
        reading = Task { [weak self] in
            do {
                guard let file = try await self?.reader.read(entry, sinceReviewed: sinceReviewed, limits: .allFiles),
                      !Task.isCancelled, let self
                else { return }
                diff.show([file], emptyMessage: "", isSameDiff: isSameDiff)
                if session.review?.revision?.includesWorkingTree == true {
                    diff.readImagesAgain()
                }
                placeThreads()
            } catch is CancellationError {
                return
            } catch is RepositoryCommandRunner.NoUsableGit {
                return
            } catch {
                Self.log.error("Reading a reviewed file's changes failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    private static func scrollKey(_ path: String, sinceReviewed: Bool) -> String {
        sinceReviewed ? "since:" + path : path
    }

    private func rememberScroll() {
        guard let shown, let scroll = diff.place.scroll else { return }
        scrolls[Self.scrollKey(shown.entry.file.path, sinceReviewed: shown.sinceReviewed)] = scroll
    }

    func windowWillClose(_: Notification) {
        reading?.cancel()
        session.stop()
        rememberScroll()
        onClose?()
    }

    func windowDidMove(_: Notification) {
        onChange?()
    }

    func windowDidResize(_: Notification) {
        onChange?()
    }

    /// Diff commands reach the diff wherever focus is in the window, and commands for the whole
    /// repository reach its window.
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if DiffViewController.windowActions.contains(action) {
            return diff
        }
        if ReviewCommands.actions.contains(action) {
            return reviewCommands
        }
        if RepositoryWindowController.repositoryActions.contains(action) {
            return repositoryWindow?.repositoryTarget(for: action)
        }
        return super.supplementalTarget(forAction: action, sender: sender)
    }
}

/// The title, and the lock, as they change with the window open.
extension ReviewWindowController {
    /// The review's name, with the repository first in the subtitle, so it's the last thing a
    /// narrow window cuts.
    private func showTitle() {
        guard let review = session.review else { return }
        window?.title = review.title
        let comparison = review.name == nil ? nil : review.comparison
        window?.subtitle = [repositoryName, comparison].compactMap(\.self).joined(separator: " · ")
    }

    /// The title follows a rename, and the list follows its points as they're changed.
    private func followReview() {
        withObservationTracking {
            showTitle()
        } onChange: { [weak self] in
            Task { @MainActor in self?.followReview() }
        }
    }

    /// The trial ending with the window open puts the lock in place of the review.
    private func followEntitlement() {
        let isLocked = withObservationTracking {
            !EntitlementStore.shared.isEntitled
        } onChange: { [weak self] in
            Task { @MainActor in self?.followEntitlement() }
        }
        guard isLocked != self.isLocked || window?.contentViewController == nil else { return }
        self.isLocked = isLocked
        let frame = window?.frame
        window?.contentViewController = isLocked ? NSHostingController(rootView: ReviewLockedView()) : split
        if let frame {
            window?.setFrame(frame, display: true)
        }
        if !isLocked {
            showSelection(force: true)
        }
    }

    private func chooseCommit(isBase: Bool) {
        Task { [weak self] in
            guard let self, let review = session.review,
                  let hash = await ReviewCommitPrompt.ask(on: window, commands: session.commands)
            else { return }
            session.setPoints(base: isBase ? .commit(hash) : review.base, head: isBase ? review.head : .commit(hash))
        }
    }
}
