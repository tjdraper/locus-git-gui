import AppKit
import os
import SwiftUI

/// The right-hand column: the commit selected in the history, with its changes below.
final class CommitDetailViewController: NSViewController {
    /// Commands the window passes on from whichever column has focus.
    static let windowActions: Set<Selector> = [#selector(toggleFullMessage(_:))]
    /// Past this, an image isn't read, only its size.
    private static let imageByteLimit = DiffImage.byteLimit

    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "CommitDetail")
    /// Holding an arrow key down in the history passes over commits faster than they can be read,
    /// so a read waits this long for the selection to settle.
    private static let settleDelay: Duration = .milliseconds(80)

    var showFailure: ((GitFailure, _ retry: @escaping () -> Void) -> Void)? {
        didSet {
            diff.showFailure = showFailure
        }
    }

    /// A file's changes in a window of their own, as they are in the shown commit.
    var openFileWindow: ((FileWindowRequest) -> Void)?

    let diff: DiffViewController
    private let commands: RepositoryCommandRunner
    private let header = CommitHeader()
    private lazy var headerController = NSHostingController(rootView: CommitHeaderView(model: header))
    /// Set from the header's height at the column's width. A hosting view's own intrinsic size is
    /// its ideal size, a subject on one line however narrow the column, which would cut off a
    /// subject that wraps.
    private lazy var headerHeight = headerController.view.heightAnchor.constraint(equalToConstant: 0)
    private let placeholder = CommitDetailPlaceholder()
    private lazy var placeholderView = NSHostingView(rootView: CommitDetailPlaceholderView(model: placeholder))
    private var failure: GitFailure?
    private var reading: Task<Void, Never>?
    private var readingSignature: Task<Void, Never>?

    init(commands: RepositoryCommandRunner, diffOptions: DiffOptionsStore) {
        self.commands = commands
        diff = DiffViewController(options: diffOptions, workTree: commands.repository.workTree)
        super.init(nibName: nil, bundle: nil)
        placeholder.showDetails = { [weak self] in
            guard let self, let failure else { return }
            showFailure?(failure) { [weak self] in self?.read() }
        }
        diff.readImage = { [commands] file, isNew in
            try await Self.readImage(isNew ? file.newObject : file.oldObject, running: commands.run)
        }
        diff.openFileWindow = { [weak self] file in
            guard let self, let commit = header.commit else { return }
            openFileWindow?(FileWindowRequest(commit: commit, file: file, files: diff.files.map(\.changed)))
        }
        diffOptions.observe(self) { [weak self] _ in self?.read(isSameDiff: true) }
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

    var labels: [CommitRefLabel] {
        header.labels
    }

    /// What Tab moves focus to, which is nothing while no commit is shown.
    var focusableView: NSView? {
        commit == nil || diff.view.isHidden ? nil : diff.focusableView
    }

    func focusChanges() {
        view.window?.makeFirstResponder(focusableView)
    }

    override func loadView() {
        let view = NSView()
        headerController.sizingOptions = []
        // Pinned over the changes, so they set its size. SwiftUI's would fix the window's height
        // to whatever the placeholder shows, which for nothing is zero.
        placeholderView.sizingOptions = []
        addChild(headerController)
        addChild(diff)
        let headerView = headerController.view
        let changesView = diff.view
        for subview in [headerView, changesView, placeholderView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerHeight,
            changesView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            changesView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            changesView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            changesView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            // Over the changes only, since the header still has the commit when its changes fail.
            // With no commit the header is empty, and the changes start at the top.
            placeholderView.topAnchor.constraint(equalTo: changesView.topAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: changesView.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: changesView.trailingAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: changesView.bottomAnchor),
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
        header.signature = nil
        header.isSignatureUnavailable = false
        diff.clear()
        read()
        readingSignature?.cancel()
        if let hash = commit?.hash {
            readSignature(of: hash)
        }
    }

    /// Kept up to date as refreshes move branches and tags onto or off the commit.
    func showLabels(_ labels: [CommitRefLabel]) {
        guard labels != header.labels else { return }
        header.labels = labels
    }

    /// `isSameDiff` reads the same commit again, such as with other diff options, keeping the diff's
    /// place and collapsed files.
    private func read(isSameDiff: Bool = false) {
        reading?.cancel()
        failure = nil
        updatePlaceholder()
        guard let hash = header.commit?.hash else { return }
        let options = diff.options.options
        reading = Task { [weak self, commands] in
            if !isSameDiff {
                try? await Task.sleep(for: Self.settleDelay)
            }
            guard !Task.isCancelled else { return }
            do {
                let started = ContinuousClock.now
                let detail = try await CommitDetail.read(hash, options: options, running: commands.run, readingPatch: commands.readPatch)
                guard !Task.isCancelled else { return }
                let elapsed = ContinuousClock.now - started
                Self.log.info("Read a commit's \(detail.files.count) files in \(elapsed, privacy: .public)")
                self?.show(detail, of: hash, isSameDiff: isSameDiff)
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

    /// Read on its own, since GPG can take a moment and the rest shouldn't wait for it. A signature
    /// that can't be read is left out of the header, not reported, since it's never what the user
    /// was looking for.
    private func readSignature(of hash: String) {
        readingSignature?.cancel()
        readingSignature = Task { [weak self, commands] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            do {
                let signature = try await CommitSignature.read(hash, running: commands.run)
                guard !Task.isCancelled else { return }
                self?.header.signature = signature
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.header.isSignatureUnavailable = true
                Self.log.error("Reading a signature failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    private func show(_ detail: CommitDetail, of hash: String, isSameDiff: Bool) {
        header.body = detail.body
        diff.readFile = { [commands, options = diff.options] file in
            try await CommitDetail.readFile(file, of: hash, options: options.options, readingPatch: commands.readPatch)
        }
        diff.show(detail.files, emptyMessage: "This commit changes no files.", isSameDiff: isSameDiff)
        updatePlaceholder()
    }

    /// `cat-file -s` first, so an image too large to show isn't read into memory.
    static func readImage(
        _ object: String?,
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async throws -> (data: Data?, byteCount: Int)? {
        guard let object else { return nil }
        let size = try await GitReadFailure.read("image size", with: .reading(["cat-file", "-s", object]), running: run) { output in
            guard let size = Int(try UnreadableGitOutput.text(output).trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw UnreadableGitOutput(reason: "Object size isn’t a number")
            }
            return size
        }
        guard size <= imageByteLimit else { return (nil, size) }
        let data = try await GitReadFailure.read("image", with: .reading(["cat-file", "blob", object]), running: run) { $0 }
        return (data, size)
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
            _ = header.signature
            _ = header.isSignatureUnavailable
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
        updatePlaceholder()
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
        // Hidden until the header has its height. Shown before that, the diff's scroll view sits
        // right under the toolbar for a moment, and macOS then draws the column's divider up through
        // the toolbar for as long as the window is open.
        diff.view.isHidden = state != .hidden || headerHeight.constant < 1
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
