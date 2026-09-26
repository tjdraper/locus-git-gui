import AppKit
import os

/// A diff of any number of files: a commit's changes in the detail column or a commit window, or
/// one file's in a file window. Side by side when there's room for both versions, and inline when
/// there isn't. Where the changes come from is up to whoever shows them, through `readFile` and
/// `readImage`.
final class DiffViewController: NSViewController {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "DiffView")
    private static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    /// Reads a file's changes whatever their size, for changes that were left out.
    var readFile: ((ChangedFile) async throws -> DiffFile)? {
        get { leftOut.read }
        set { leftOut.read = newValue }
    }

    var readImage: ((ChangedFile, _ isNew: Bool) async throws -> (data: Data?, byteCount: Int)?)? {
        get { images.read }
        set { images.read = newValue }
    }

    var openFileWindow: ((DiffFile) -> Void)?
    var showFailure: ((GitFailure, _ retry: @escaping () -> Void) -> Void)?
    /// Whether a file window can be opened from here, which a file window itself can't.
    var opensFileWindows = true
    /// The bar above the files, which a diff of one file has no need for.
    var showsSummary = true {
        didSet { updateSummary() }
    }
    /// Where Next File and Previous File go when the files are somewhere other than this diff, as in
    /// a file window, which shows one of a commit's files at a time.
    var adjacentFiles: AdjacentFiles?

    struct AdjacentFiles {
        let canGo: (_ offset: Int) -> Bool
        let move: (_ offset: Int) -> Void
    }

    let options: DiffOptionsStore
    let workTree: URL
    let canvas = DiffCanvasView()
    private let scrollView = NSScrollView()
    private let clipView = DiffClipView()
    private(set) lazy var blockViews = DiffBlockViews(canvas: canvas)
    private let images = DiffImageStore()
    private let leftOut = LeftOutChangesReader()
    private let emptyMessage = NSTextField(labelWithString: "")
    private let summaryBar = DiffSummaryBar()
    private lazy var summaryHeight = summaryBar.heightAnchor.constraint(equalToConstant: 0)
    private let metrics: DiffLayout.Metrics
    private let painter: DiffRowPainter

    private(set) var files: [DiffFile] = []
    var collapsedPaths: Set<String> = []
    private var numberColumns = 3
    private var shownWidth = 0.0
    private var workingTreePresence: [String: Bool] = [:]

    init(options: DiffOptionsStore, workTree: URL) {
        self.options = options
        self.workTree = workTree
        let advance = ("0" as NSString).size(withAttributes: [.font: Self.font]).width
        let fontHeight = Self.font.ascender - Self.font.descender + Self.font.leading
        metrics = DiffLayout.Metrics(advance: advance, lineHeight: (fontHeight + 5).rounded(.up))
        painter = DiffRowPainter(font: Self.font, metrics: metrics)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// What Tab moves focus to, which is nothing while there are no changes.
    var focusableView: NSView? {
        files.isEmpty ? nil : canvas
    }

    override func loadView() {
        let view = NSView()
        scrollView.contentView = clipView
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.backgroundColor = .textBackgroundColor
        clipView.onScroll = { [weak self] in self?.blockViews.update() }
        images.onLoad = { [weak self] in self?.blockViews.update() }
        canvas.setAccessibilityLabel("Changes")
        canvas.setAccessibilityRole(.textArea)
        canvas.makeMenu = { [weak self] file in
            guard let self, let file else { return nil }
            let copies = canvas.selection.map { !$0.isEmpty } ?? false
            return menu(forFile: file).make(copying: copies ? canvas : nil)
        }
        emptyMessage.textColor = .secondaryLabelColor
        emptyMessage.alignment = .center
        emptyMessage.isHidden = true
        blockViews.configureHeader = { [weak self] view, file in self?.configure(view, file: file) }
        blockViews.configureNotice = { [weak self] view, file, notice in self?.configure(view, file: file, notice: notice) }
        blockViews.configureImages = { [weak self] view, file in
            guard let self else { return }
            view.show(images.state(of: files[file].changed))
        }
        summaryBar.onCollapseAll = { [weak self] in self?.collapseAllFiles(nil) }
        summaryBar.onExpandAll = { [weak self] in self?.expandAllFiles(nil) }
        for subview in [summaryBar, scrollView, emptyMessage] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            summaryBar.topAnchor.constraint(equalTo: view.topAnchor),
            summaryBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            summaryBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            summaryHeight,
            scrollView.topAnchor.constraint(equalTo: summaryBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyMessage.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            emptyMessage.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            emptyMessage.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
        self.view = view
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard abs(clipView.bounds.width - shownWidth) >= 0.5 else { return }
        rebuild(keepingPlace: true)
    }

    /// `isSameDiff` keeps which files are collapsed and where the diff is scrolled to, for the same
    /// changes read again, such as with other options.
    func show(_ files: [DiffFile], emptyMessage message: String, isSameDiff: Bool) {
        _ = view
        if !isSameDiff {
            collapsedPaths = []
            images.removeAll()
            workingTreePresence = [:]
        }
        leftOut.cancelAll()
        self.files = files
        numberColumns = DiffLayout.numberColumns(of: files)
        emptyMessage.stringValue = message
        emptyMessage.isHidden = !files.isEmpty
        blockViews.removeAll()
        rebuild(keepingPlace: isSameDiff)
        if !isSameDiff {
            canvas.scroll(to: 0)
        }
    }

    func clear() {
        show([], emptyMessage: "", isSameDiff: false)
    }

    func focus() {
        view.window?.makeFirstResponder(focusableView)
    }

    /// Builds the rows again and lays them out at the current width. `keepingPlace` keeps the row
    /// at the top where it was.
    func rebuild(keepingPlace: Bool) {
        updateSummary()
        let width = clipView.bounds.width
        shownWidth = width
        let anchor = keepingPlace ? canvas.content.flatMap { content in
            DiffScrollAnchor(top: canvas.visibleRect.minY, document: content.document, layout: content.layout, files: content.files)
        } : nil
        guard !files.isEmpty, width > 0 else {
            canvas.show(nil, keepingSelection: false)
            canvas.frame = NSRect(x: 0, y: 0, width: max(width, 0), height: 0)
            blockViews.update()
            return
        }
        let started = ContinuousClock.now
        let style = DiffLayout.style(forWidth: width, metrics: metrics, numberColumns: numberColumns)
        let collapsed = Set(files.indices.filter { collapsedPaths.contains(files[$0].changed.path) })
        let document = DiffDocument(files: files, collapsed: collapsed, style: style)
        let layout = DiffLayout(document: document, files: files, metrics: metrics, width: width, numberColumns: numberColumns)
        let isSameShape = canvas.content.map { $0.document == document } ?? false
        canvas.show(
            DiffCanvasView.Content(files: files, document: document, layout: layout, painter: painter),
            keepingSelection: isSameShape
        )
        canvas.frame = NSRect(x: 0, y: 0, width: width, height: layout.height)
        if !isSameShape {
            blockViews.removeAll()
        }
        if let top = anchor?.top(in: document, layout: layout, files: files) {
            canvas.scroll(to: top)
        }
        blockViews.update()
        let elapsed = ContinuousClock.now - started
        Self.log.info("Laid out \(document.blocks.count) rows in \(elapsed, privacy: .public)")
    }

    private func updateSummary() {
        guard isViewLoaded else { return }
        let isShown = showsSummary && !files.isEmpty
        summaryBar.isHidden = !isShown
        summaryHeight.constant = isShown ? DiffSummaryBar.height : 0
        summaryBar.show(files: files, isAllCollapsed: files.allSatisfy { collapsedPaths.contains($0.changed.path) })
    }

    private func configure(_ view: DiffFileHeaderView, file index: Int) {
        let file = files[index]
        let path = file.changed.path
        view.show(DiffFileHeaderView.Content(
            file: file.changed,
            added: file.patch.added,
            removed: file.patch.removed,
            isCollapsed: collapsedPaths.contains(path),
            isInWorkingTree: isInWorkingTree(path)
        ))
        view.onToggle = { [weak self] in self?.toggleCollapsed(path) }
        view.onToggleAll = { [weak self] in self?.toggleAllCollapsed(like: path) }
        view.onOpenInEditor = { [weak self] in self?.openInEditor(path: path) }
        view.makeMenu = { [weak self] in
            guard let self, let index = self.index(of: path) else { return NSMenu() }
            return menu(forFile: index).make()
        }
    }

    private func configure(_ view: DiffNoticeView, file index: Int, notice: DiffDocument.Notice) {
        view.show(notice)
        let path = files[index].changed.path
        view.onShow = { [weak self] in self?.showChanges(ofFile: path) }
        view.onShowDetails = { [weak self] in
            guard let self, let failure = leftOut.failure(for: path) else { return }
            showFailure?(failure) { [weak self] in self?.showChanges(ofFile: path) }
        }
    }

    func index(of path: String) -> Int? {
        files.firstIndex { $0.changed.path == path }
    }

    func isInWorkingTree(_ path: String) -> Bool {
        if let known = workingTreePresence[path] {
            return known
        }
        let exists = WorkingTreeFile(path: path, in: workTree).exists
        workingTreePresence[path] = exists
        return exists
    }

    /// Reads a file's left-out changes, or tries again after a failure.
    private func showChanges(ofFile path: String) {
        guard leftOut.canRead, let index = index(of: path) else { return }
        files[index].reading = .reading
        rebuild(keepingPlace: true)
        leftOut.start(files[index].changed) { [weak self] result in
            guard let self, let index = self.index(of: path) else { return }
            switch result {
            case let .success(file):
                files[index] = file
                numberColumns = DiffLayout.numberColumns(of: files)
            case let .failure(failed):
                files[index].reading = .failed(summary: failed.summary)
            }
            rebuild(keepingPlace: true)
        }
    }

    var commandTarget: DiffCommandTarget? {
        guard let content = canvas.content else { return nil }
        return DiffCommandTarget(
            document: content.document,
            layout: content.layout,
            selection: canvas.selection,
            visibleTop: canvas.visibleRect.minY + content.layout.metrics.headerHeight,
            visibleBottom: canvas.visibleRect.maxY
        )
    }
}

/// Collapsing and expanding files, from their headers and the summary bar.
extension DiffViewController {
    func toggleCollapsed(_ path: String) {
        if collapsedPaths.contains(path) {
            collapsedPaths.remove(path)
        } else {
            collapsedPaths.insert(path)
        }
        rebuildKeepingHeader(of: path)
    }

    /// Option-click, as in Finder: every file goes the way the clicked one would.
    func toggleAllCollapsed(like path: String) {
        collapsedPaths = collapsedPaths.contains(path) ? [] : Set(files.map(\.changed.path))
        rebuildKeepingHeader(of: path)
    }

    /// Keeps a file's header where it was on screen when the file collapses or expands under it,
    /// or at the top when it was stuck there.
    func rebuildKeepingHeader(of path: String) {
        guard let content = canvas.content, let file = index(of: path) else {
            rebuild(keepingPlace: true)
            return
        }
        let distance = max(content.layout.top(of: content.document.fileStarts[file]) - canvas.visibleRect.minY, 0)
        rebuild(keepingPlace: false)
        guard let rebuilt = canvas.content else { return }
        canvas.scroll(to: rebuilt.layout.top(of: rebuilt.document.fileStarts[file]) - distance)
        blockViews.update()
    }
}

/// What can be done with one file in the diff, from its header, its menu or the menu bar.
extension DiffViewController {
    func openInEditor(path: String) {
        let file = WorkingTreeFile(path: path, in: workTree)
        guard file.exists else {
            NSSound.beep()
            return
        }
        file.openInEditor()
    }

    func openFileWindow(path: String) {
        guard opensFileWindows, let index = index(of: path) else { return }
        openFileWindow?(files[index])
    }

    func menu(forFile index: Int) -> ChangedFileMenu {
        let path = files[index].changed.path
        let file = WorkingTreeFile(path: path, in: workTree)
        return ChangedFileMenu(
            isInWorkingTree: isInWorkingTree(path),
            opensFileWindows: opensFileWindows,
            isCollapsed: collapsedPaths.contains(path),
            openInEditor: { [weak self] in self?.openInEditor(path: path) },
            revealInFinder: file.revealInFinder,
            copyAbsolutePath: file.copyAbsolutePath,
            copyPathFromRepositoryRoot: file.copyPathFromRepositoryRoot,
            openFileWindow: { [weak self] in self?.openFileWindow(path: path) },
            toggleCollapsed: { [weak self] in self?.toggleCollapsed(path) }
        )
    }
}

/// Reports every scroll as it happens, so the file headers move with the diff in the same frame
/// rather than a moment after, as they would waiting for a notification. Scrolling from the keyboard
/// and the scroll bar goes through `scroll(to:)` without setting the bounds' origin, and the
/// trackpad sets the origin directly.
private final class DiffClipView: NSClipView {
    var onScroll: (() -> Void)?

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: newOrigin)
        onScroll?()
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(newOrigin)
        onScroll?()
    }
}
