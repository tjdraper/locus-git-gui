import AppKit
import os

/// One file's changes in one commit, in a window of their own, read whatever their size. Previous
/// File and Next File move through the rest of the commit's files in the same window.
final class FileWindowController: NSWindowController, NSWindowDelegate {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "FileWindow")
    private static let contentSize = NSSize(width: 900, height: 760)
    private static let previousItem = NSToolbarItem.Identifier("PreviousFile")
    private static let nextItem = NSToolbarItem.Identifier("NextFile")
    /// Single keys, as in a mail or news reader, since the window has nothing to type into.
    private static let previousKey = "j"
    private static let nextKey = "k"

    let commit: Commit
    var onClose: (() -> Void)?
    private let files: [ChangedFile]
    private var index: Int
    private let repositoryName: String
    private let diff: DiffViewController
    private let commands: RepositoryCommandRunner
    private let failureSheet = GitFailureSheetPresenter()
    private var reading: Task<Void, Never>?

    init(_ request: FileWindowRequest, repositoryName: String, commands: RepositoryCommandRunner, diffOptions: DiffOptionsStore) {
        commit = request.commit
        files = request.files
        index = request.files.firstIndex { $0.path == request.file.changed.path } ?? 0
        self.repositoryName = repositoryName
        self.commands = commands
        diff = DiffViewController(options: diffOptions, workTree: commands.repository.workTree)
        diff.opensFileWindows = false
        diff.showsSummary = false
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

    var path: String {
        files.indices.contains(index) ? files[index].path : ""
    }

    private func connectDiff(_ diffOptions: DiffOptionsStore) {
        diff.showFailure = { [weak self] failure, retry in
            guard let self, let window else { return }
            failureSheet.present(failure, repository: commands.repository, on: window, wasOpenedByUser: true, retry: retry)
        }
        diff.readFile = { [weak self] file in
            guard let self else { throw CancellationError() }
            return try await readWhole(file)
        }
        diff.readImage = { [commands] file, isNew in
            try await CommitDetailViewController.readImage(isNew ? file.newObject : file.oldObject, running: commands.run)
        }
        diff.adjacentFiles = DiffViewController.AdjacentFiles(
            canGo: { [weak self] offset in self?.files.indices.contains((self?.index ?? -1) + offset) ?? false },
            move: { [weak self] offset in self?.goToFile(offset: offset) }
        )
        diff.canvas.onTypedKey = { [weak self] key in
            switch key {
            case Self.previousKey: self?.goToFile(offset: -1)
            case Self.nextKey: self?.goToFile(offset: 1)
            default: return false
            }
            return true
        }
        diffOptions.observe(self) { [weak self] _ in
            guard let self, files.indices.contains(index) else { return }
            read(files[index], isSameDiff: true)
        }
    }

    /// What's already been read shows at once, and the whole file follows.
    private func show(_ file: DiffFile) {
        window?.title = (file.changed.path as NSString).lastPathComponent
        let folder = (file.changed.path as NSString).deletingLastPathComponent
        window?.subtitle = [folder.isEmpty ? nil : folder, String(commit.hash.prefix(7)), repositoryName]
            .compactMap(\.self)
            .joined(separator: " · ")
        diff.show([file], emptyMessage: "", isSameDiff: false)
        read(file.changed, isSameDiff: true)
    }

    private func goToFile(offset: Int) {
        guard files.indices.contains(index + offset) else {
            NSSound.beep()
            return
        }
        index += offset
        var file = DiffFile(changed: files[index], patch: FilePatch())
        file.reading = .reading
        show(file)
        window?.toolbar?.validateVisibleItems()
    }

    private func read(_ changed: ChangedFile, isSameDiff: Bool) {
        reading?.cancel()
        reading = Task { [weak self] in
            do {
                guard let file = try await self?.readWhole(changed), !Task.isCancelled, let self else { return }
                diff.show([file], emptyMessage: "", isSameDiff: isSameDiff)
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

    private func readWhole(_ file: ChangedFile) async throws -> DiffFile {
        try await CommitDetail.readFile(file, of: commit.hash, options: diff.options.options, readingPatch: commands.readPatch)
    }

    func windowWillClose(_: Notification) {
        reading?.cancel()
        onClose?()
    }

    /// Diff commands reach the diff wherever focus is in the window.
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        DiffViewController.windowActions.contains(action) ? diff : super.supplementalTarget(forAction: action, sender: sender)
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
        item.toolTip = "\(command.title) (\((isNext ? Self.nextKey : Self.previousKey).uppercased()))"
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
