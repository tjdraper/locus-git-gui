import AppKit
import os
import SwiftUI

/// The right-hand column: the commit selected in the history, with its changes below.
final class CommitDetailViewController: NSViewController {
    /// Commands the window passes on from whichever column has focus.
    static let windowActions: Set<Selector> = [#selector(toggleFullMessage(_:))]

    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "CommitDetail")
    /// Holding an arrow key down in the history passes over commits faster than they can be read,
    /// so a read waits this long for the selection to settle.
    private static let settleDelay: Duration = .milliseconds(80)

    var showFailure: ((GitFailure, _ retry: @escaping () -> Void) -> Void)?

    private let run: (GitCommand) async throws -> ChildProcess.Result
    private let header = CommitHeader()
    private lazy var headerController = NSHostingController(rootView: CommitHeaderView(model: header))
    /// Set from the header's height at the column's width. A hosting view's own intrinsic size is
    /// its ideal size, a subject on one line however narrow the column, which would cut off a
    /// subject that wraps.
    private lazy var headerHeight = headerController.view.heightAnchor.constraint(equalToConstant: 0)
    private let changesScrollView = NSTextView.scrollableTextView()
    private let placeholder = CommitDetailPlaceholder()
    private lazy var placeholderView = NSHostingView(rootView: CommitDetailPlaceholderView(model: placeholder))
    private var failure: GitFailure?
    private var reading: Task<Void, Never>?

    init(run: @escaping (GitCommand) async throws -> ChildProcess.Result) {
        self.run = run
        super.init(nibName: nil, bundle: nil)
        placeholder.showDetails = { [weak self] in
            guard let self, let failure else { return }
            showFailure?(failure) { [weak self] in self?.read() }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    var goToCommit: ((String) -> Void)? {
        get { header.goToCommit }
        set { header.goToCommit = newValue }
    }

    var reveal: ((SidebarItemID) -> Void)? {
        get { header.reveal }
        set { header.reveal = newValue }
    }

    var commit: Commit? {
        header.commit
    }

    /// What Tab moves focus to, which is nothing while no commit is shown.
    var focusableView: NSView? {
        commit == nil || changesScrollView.isHidden ? nil : changesView
    }

    func focusChanges() {
        view.window?.makeFirstResponder(focusableView)
    }

    private var changesView: NSTextView? {
        changesScrollView.documentView as? NSTextView
    }

    override func loadView() {
        let view = NSView()
        if let changesView {
            changesView.isEditable = false
            changesView.isSelectable = true
            changesView.textContainerInset = NSSize(width: 8, height: 8)
            changesView.setAccessibilityLabel("Changes")
        }
        changesScrollView.automaticallyAdjustsContentInsets = false
        headerController.sizingOptions = []
        // Pinned over the changes, so they set its size. SwiftUI's would fix the window's height
        // to whatever the placeholder shows, which for nothing is zero.
        placeholderView.sizingOptions = []
        addChild(headerController)
        let headerView = headerController.view
        for subview in [headerView, changesScrollView, placeholderView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerHeight,
            changesScrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            changesScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            changesScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            changesScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            // Over the changes only, since the header still has the commit when its changes fail.
            // With no commit the header is empty, and the changes start at the top.
            placeholderView.topAnchor.constraint(equalTo: changesScrollView.topAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: changesScrollView.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: changesScrollView.trailingAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: changesScrollView.bottomAnchor),
        ])
        self.view = view
        updatePlaceholder()
        followHeaderSize()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateHeaderHeight()
    }

    func show(_ commit: Commit?, labels: [CommitRefLabel]) {
        header.labels = labels
        guard commit?.hash != header.commit?.hash else { return }
        header.commit = commit
        header.body = nil
        changesView?.string = ""
        read()
    }

    /// Kept up to date as refreshes move branches and tags onto or off the commit.
    func showLabels(_ labels: [CommitRefLabel]) {
        guard labels != header.labels else { return }
        header.labels = labels
    }

    private func read() {
        reading?.cancel()
        failure = nil
        updatePlaceholder()
        guard let hash = header.commit?.hash else { return }
        reading = Task { [weak self, run] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            do {
                let detail = try await CommitDetail.read(hash, running: run)
                guard !Task.isCancelled else { return }
                self?.show(detail)
            } catch is CancellationError {
                return
            } catch is RepositoryCommandRunner.NoUsableGit {
                return
            } catch let failure as GitReadFailure {
                self?.fail(GitFailure(
                    summary: failure.outputWasUnreadable
                        ? "Locus Git Gui couldn’t read Git’s report on this commit’s \(failure.subject)."
                        : "Git couldn’t read this commit’s \(failure.subject).",
                    arguments: failure.command.arguments,
                    result: failure.result
                ))
            } catch {
                Self.log.error("Reading a commit failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    private func show(_ detail: CommitDetail) {
        header.body = detail.body
        changesView?.textStorage?.setAttributedString(CommitChangesText.make(detail))
        changesView?.scrollToBeginningOfDocument(nil)
        updatePlaceholder()
    }

    private func fail(_ failure: GitFailure) {
        self.failure = failure
        updatePlaceholder()
    }

    /// Measured again whenever what the header shows changes, including the message being expanded
    /// from the header's own button.
    private func followHeaderSize() {
        withObservationTracking {
            _ = header.commit
            _ = header.body
            _ = header.labels
            _ = header.isMessageExpanded
        } onChange: { [weak self] in
            // Called before the change is made, so the header is measured once it has been.
            Task { @MainActor in
                self?.updateHeaderHeight()
                self?.followHeaderSize()
            }
        }
    }

    private func updateHeaderHeight() {
        let width = view.bounds.width
        let height = header.commit == nil || width <= 0
            ? 0
            : headerController.sizeThatFits(in: NSSize(width: width, height: .greatestFiniteMagnitude)).height
        guard abs(headerHeight.constant - height) >= 0.5 else { return }
        headerHeight.constant = height
    }

    private func updatePlaceholder() {
        let state: CommitDetailPlaceholder.State = if let failure {
            .failed(summary: failure.summary)
        } else if header.commit == nil {
            .noCommit
        } else {
            .hidden
        }
        placeholder.state = state
        placeholderView.isHidden = state == .hidden
        changesScrollView.isHidden = state != .hidden
    }

    @objc func toggleFullMessage(_: Any?) {
        header.isMessageExpanded.toggle()
    }
}

extension CommitDetailViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(toggleFullMessage(_:)) else { return true }
        menuItem.title = header.isMessageExpanded ? "Hide Full Message" : AppCommand.showFullMessage.title
        return header.body != nil
    }
}
