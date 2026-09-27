import AppKit
import os

/// One file's changes in one commit, or in the working area, in a window of their own, read whatever
/// their size. Previous File and Next File move through the rest of the commit's or the working
/// area's files in the same window.
final class FileWindowController: NSWindowController, NSWindowDelegate {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "FileWindow")
    private static let contentSize = NSSize(width: 900, height: 760)
    private static let previousItem = NSToolbarItem.Identifier("PreviousFile")
    private static let nextItem = NSToolbarItem.Identifier("NextFile")

    let source: FileWindowRequest.Source
    var onClose: (() -> Void)?
    /// When the window moves, scrolls or shows another file, for the repository to remember.
    var onChange: (() -> Void)?
    /// Where the file was left, until it's been read and can be scrolled there.
    var pendingScroll: DiffScrollAnchor?
    weak var repositoryWindow: RepositoryWindowController?
    private var files: [DiffFile]
    /// The file shown, which stays the same while a refresh takes it out of `files`.
    private(set) var file: DiffFile.Identity
    /// Where Previous File and Next File count from.
    private var index: Int
    private var repositoryName: String
    private let diff: DiffViewController
    private let commands: RepositoryCommandRunner
    private let failureSheet = GitFailureSheetPresenter()
    private var reading: Task<Void, Never>?
    /// The file the title bar names, which stays while a refresh takes it out of `files`.
    private var titled: DiffFile?

    init(_ request: FileWindowRequest, repositoryName: String, commands: RepositoryCommandRunner, diffOptions: DiffOptionsStore) {
        source = request.source
        files = request.files
        index = request.files.firstIndex { $0.id == request.file.id } ?? 0
        file = request.file.id
        self.repositoryName = repositoryName
        self.commands = commands
        diff = DiffViewController(options: diffOptions, workTree: commands.repository.workTree)
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
        // Files aren't brought back after a relaunch, only repositories.
        window.isRestorable = false
        // Kept apart from repository and commit windows, which would otherwise take them as tabs.
        window.tabbingIdentifier = "FileWindow"
        window.toolbarStyle = .unified
        super.init(window: window)
        let toolbar = NSToolbar(identifier: "FileWindow")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.contentViewController = diff
        window.setContentSize(Self.contentSize)
        window.delegate = self
        connectDiff(diffOptions)
        show(request.file)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// The working area's files as of the latest refresh. The file shown is read again, since its
    /// changes may have changed while its name didn't.
    func showWorkingArea(_ files: [DiffFile]) {
        guard source == .workingArea else { return }
        self.files = files
        guard let found = files.firstIndex(where: { $0.id == file }) else {
            index = min(index, max(files.count - 1, 0))
            diff.show([], emptyMessage: Self.goneMessage(file), isSameDiff: false)
            window?.toolbar?.validateVisibleItems()
            return
        }
        index = found
        read(files[found], isSameDiff: true)
        window?.toolbar?.validateVisibleItems()
    }

    private static func goneMessage(_ file: DiffFile.Identity) -> String {
        switch file.group.flatMap(WorkingAreaGroup.init(rawValue:)) {
        case .staged: "Nothing in this file is staged now."
        case .unstaged: "Nothing in this file is unstaged now."
        case .untracked: "This file isn’t untracked now."
        case .conflicted: "This file has no conflict now."
        case nil: ""
        }
    }

    private func connectDiff(_ diffOptions: DiffOptionsStore) {
        diff.showFailure = { [weak self] failure, retry in
            guard let self, let window else { return }
            failureSheet.present(failure, repository: commands.repository, on: window, wasOpenedByUser: true, retry: retry)
        }
        diff.onPlaceChange = { [weak self] _ in self?.onChange?() }
        diff.readFile = { [weak self] file in
            guard let self else { throw CancellationError() }
            return try await readWhole(file)
        }
        diff.readImage = { [commands, source] file, isNew in
            guard source == .workingArea else {
                let object = isNew ? file.changed.newObject : file.changed.oldObject
                return try await CommitDetailViewController.readImage(object, running: commands.run)
            }
            return try await WorkingAreaImages.read(file, isNew: isNew, workTree: commands.repository.workTree, running: commands.run)
        }
        diff.adjacentFiles = DiffViewController.AdjacentFiles(
            canGo: { [weak self] offset in self?.files.indices.contains((self?.index ?? -1) + offset) ?? false },
            move: { [weak self] offset in self?.goToFile(offset: offset) }
        )
        diffOptions.observe(self) { [weak self] _ in
            guard let self, let shown = files.first(where: { $0.id == file }) else { return }
            read(shown, isSameDiff: true)
        }
    }

    /// What's already been read shows at once, and the whole file follows.
    private func show(_ file: DiffFile) {
        window?.title = (file.changed.path as NSString).lastPathComponent
        showSubtitle(for: file)
        diff.show([file], emptyMessage: "", isSameDiff: false)
        read(file, isSameDiff: true)
        onChange?()
    }

    var record: OpenWindows.FileWindow {
        let commit: String? = switch source {
        case let .commit(commit): commit.hash
        case .workingArea: nil
        }
        return OpenWindows.FileWindow(commit: commit, file: file, frame: window?.frameDescriptor, scroll: diff.place.scroll)
    }

    func showRepositoryName(_ name: String) {
        repositoryName = name
        if let titled {
            showSubtitle(for: titled)
        }
    }

    /// The repository first, so it's the last thing a narrow window cuts.
    private func showSubtitle(for file: DiffFile) {
        titled = file
        let folder = (file.changed.path as NSString).deletingLastPathComponent
        let origin = switch source {
        case let .commit(commit): String(commit.hash.prefix(7))
        case .workingArea: WorkingAreaGroup(file)?.title
        }
        window?.subtitle = [repositoryName, origin, folder.isEmpty ? nil : folder]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    private func goToFile(offset: Int) {
        guard files.indices.contains(index + offset) else {
            NSSound.beep()
            return
        }
        index += offset
        file = files[index].id
        var placeholder = DiffFile(changed: files[index].changed, patch: FilePatch(), group: files[index].group)
        placeholder.reading = .reading
        show(placeholder)
        window?.toolbar?.validateVisibleItems()
    }

    private func read(_ shown: DiffFile, isSameDiff: Bool) {
        reading?.cancel()
        reading = Task { [weak self] in
            do {
                guard let file = try await self?.readWhole(shown), !Task.isCancelled, let self else { return }
                diff.show([file], emptyMessage: "", isSameDiff: isSameDiff)
                if let pendingScroll {
                    self.pendingScroll = nil
                    diff.scroll(to: pendingScroll)
                }
                if source == .workingArea {
                    diff.readImagesAgain()
                }
                if window?.firstResponder === window {
                    diff.focus()
                }
            } catch is CancellationError {
                return
            } catch is RepositoryCommandRunner.NoUsableGit {
                return
            } catch {
                Self.log.error("Reading a file's changes failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    private func readWhole(_ file: DiffFile) async throws -> DiffFile {
        switch source {
        case let .commit(commit):
            try await CommitDetail.readFile(file.changed, of: commit.hash, options: diff.options.options, readingPatch: commands.readPatch)
        case .workingArea:
            try await WorkingAreaDiff.readFile(
                file,
                options: diff.options.options,
                workTree: commands.repository.workTree,
                readingPatch: commands.readPatch
            )
        }
    }

    func windowWillClose(_: Notification) {
        reading?.cancel()
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
        if RepositoryWindowController.repositoryActions.contains(action) {
            return repositoryWindow?.repositoryTarget(for: action)
        }
        return super.supplementalTarget(forAction: action, sender: sender)
    }

    @objc private func goToPreviousFile(_: Any?) {
        goToFile(offset: -1)
    }

    @objc private func goToNextFile(_: Any?) {
        goToFile(offset: 1)
    }
}

extension FileWindowController: NSToolbarDelegate, NSToolbarItemValidation {
    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.previousItem, Self.nextItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        let isNext = identifier == Self.nextItem
        let command = isNext ? AppCommand.goToNextFile : .goToPreviousFile
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = command.title
        let key = isNext ? DiffViewController.nextFileKey : DiffViewController.previousFileKey
        item.toolTip = "\(command.title) (\(key.uppercased()))"
        item.image = NSImage(systemSymbolName: isNext ? "chevron.down" : "chevron.up", accessibilityDescription: command.title)
        item.isBordered = true
        item.target = self
        item.action = isNext ? #selector(goToNextFile(_:)) : #selector(goToPreviousFile(_:))
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        files.indices.contains(index + (item.itemIdentifier == Self.nextItem ? 1 : -1))
    }
}
