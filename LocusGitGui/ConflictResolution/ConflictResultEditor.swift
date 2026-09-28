import AppKit

/// The result pane: the file as it is on disk, Git's markers and all, which is edited to resolve it.
/// Its conflicts are found again shortly after each edit, so the marks, the count and taking a side
/// follow the text as it changes. Each file read gets its own undo history.
final class ConflictResultEditor: NSObject, NSTextViewDelegate {
    /// How long typing pauses before the conflicts are found again. Finding them reads the whole
    /// file, which for a large one is too slow to do on every keystroke.
    private static let settleDelay = Duration.milliseconds(150)

    let pane = ConflictTextPane(color: nil, isEditable: true)
    private(set) var markers = ConflictMarkers(parsing: "")
    /// Whether there are edits the file on disk doesn't have yet.
    private(set) var isEdited = false
    /// After the conflicts are found again, and when the edited state or the current conflict changes.
    var onChange: (() -> Void)?
    private var markerSize = ConflictMarkers.defaultMarkerSize
    /// The window's too, so Undo takes back a side taken wherever focus is in it.
    private(set) var undo = UndoManager()
    private var finding: Task<Void, Never>?
    /// Counts edits, so conflicts found in text that has since changed are thrown away.
    private var generation = 0
    private var lastCurrent: Int?

    override init() {
        super.init()
        textView.delegate = self
        pane.setTitle("Result")
    }

    var textView: ConflictTextView {
        pane.textView
    }

    var text: String {
        textView.string
    }

    /// Read from disk, with nothing to save and nothing to undo. `markers` are the text's, found
    /// away from the main actor as it was read.
    func load(_ text: String, markers: ConflictMarkers, markerSize: Int) {
        self.markerSize = markerSize
        undo = UndoManager()
        pane.setText(text)
        isEdited = false
        show(markers)
        if let first = markers.conflicts.first {
            select(first)
        }
    }

    /// The file changed on disk, such as in another editor. The place in it is kept as nearly as
    /// the new text allows.
    func reload(_ text: String) {
        let selection = textView.selectedRange()
        let scroll = textView.enclosingScrollView?.contentView.bounds.origin
        undo = UndoManager()
        textView.string = text
        isEdited = false
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        if let scroll {
            textView.enclosingScrollView?.contentView.scroll(to: scroll)
        }
        show(ConflictMarkers(parsing: text, markerSize: markerSize))
    }

    func markSaved() {
        isEdited = false
        onChange?()
    }

    /// As the text is now, even while an edit waits for its conflicts to be found again.
    var conflictCount: Int {
        findConflictsNow()
        return markers.conflicts.count
    }

    /// The conflict the cursor is in, or else the first one after it.
    var currentConflict: Int? {
        let location = textView.selectedRange().location
        return markers.index(containing: location) ?? markers.conflicts.firstIndex { $0.range.location >= location }
    }

    func goToConflict(offset: Int) {
        findConflictsNow()
        let conflicts = markers.conflicts
        guard !conflicts.isEmpty else {
            NSSound.beep()
            return
        }
        let location = textView.selectedRange().location
        let index = offset > 0
            ? conflicts.firstIndex { $0.range.location > location }
            : conflicts.lastIndex { NSMaxRange($0.range) <= location }
        guard let index else {
            NSSound.beep()
            return
        }
        select(conflicts[index])
    }

    /// Replaces the current conflict with a side, as one step to undo, and moves on to the next.
    func take(_ choice: ConflictMarkers.Choice, actionName: String) {
        findConflictsNow()
        guard let index = currentConflict else {
            NSSound.beep()
            return
        }
        let conflict = markers.conflicts[index]
        let replacement = ConflictMarkers.resolution(of: conflict, in: text as NSString, choosing: choice)
        guard textView.shouldChangeText(in: conflict.range, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: conflict.range, with: replacement)
        textView.didChangeText()
        undo.setActionName(actionName)
        findConflictsNow()
        let next = markers.conflicts.first { $0.range.location >= conflict.range.location } ?? markers.conflicts.first
        if let next {
            select(next)
        } else {
            let end = conflict.range.location + (replacement as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.scrollRangeToVisible(NSRange(location: conflict.range.location, length: 0))
        }
    }

    /// After the pane changes size, which moves the conflict the cursor is at.
    func scrollToCurrent() {
        guard let current = currentConflict else { return }
        textView.scrollToMiddle(markers.conflicts[current].range)
    }

    private func select(_ conflict: ConflictMarkers.Conflict) {
        textView.setSelectedRange(NSRange(location: conflict.range.location, length: 0))
        textView.scrollToMiddle(conflict.range)
        showCurrent()
    }

    func undoManager(for _: NSTextView) -> UndoManager? {
        undo
    }

    /// Typing and taking a side both come through here. After the trial the result can be read but
    /// not changed, like the rest of the repository, so there's nothing for Save to write.
    func textView(_ textView: NSTextView, shouldChangeTextIn _: NSRange, replacementString _: String?) -> Bool {
        ReadOnlyLock.allowsChange(in: textView.window)
    }

    func textDidChange(_: Notification) {
        generation += 1
        if !isEdited {
            isEdited = true
            onChange?()
        }
        findConflictsSoon()
    }

    func textViewDidChangeSelection(_: Notification) {
        showCurrent()
    }

    private func findConflictsSoon() {
        finding?.cancel()
        let text = text
        let expected = generation
        let markerSize = markerSize
        finding = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            let markers = await Self.find(in: text, markerSize: markerSize)
            guard !Task.isCancelled, let self, generation == expected else { return }
            show(markers)
        }
    }

    /// Before acting on the conflicts, which have to be those in the text as it is now. They already
    /// are unless an edit is waiting for them to be found again.
    private func findConflictsNow() {
        guard let finding else { return }
        finding.cancel()
        show(ConflictMarkers(parsing: text, markerSize: markerSize))
    }

    @concurrent
    private static func find(in text: String, markerSize: Int) async -> ConflictMarkers {
        ConflictMarkers(parsing: text, markerSize: markerSize)
    }

    private func show(_ markers: ConflictMarkers) {
        finding = nil
        self.markers = markers
        lastCurrent = nil
        showCurrent(force: true)
    }

    private func showCurrent(force: Bool = false) {
        let current = currentConflict
        guard force || current != lastCurrent else { return }
        lastCurrent = current
        textView.highlights = markers.conflicts.enumerated().flatMap { index, conflict in
            ConflictColors.highlights(for: conflict, isCurrent: index == current)
        }
        onChange?()
    }
}

/// The colours that mark each side, in the result and in the panes that show each version. System
/// colours at low opacity, as the diff's are, so they sit under the text in light and dark mode.
enum ConflictColors {
    static let ours = NSColor.systemBlue
    static let theirs = NSColor.systemPurple
    static let base = NSColor.systemGray

    static func fill(_ color: NSColor, isCurrent: Bool) -> NSColor {
        color.withAlphaComponent(isCurrent ? 0.26 : 0.12)
    }

    /// The marker lines take a neutral fill, and each side its own colour over it.
    static func highlights(for conflict: ConflictMarkers.Conflict, isCurrent: Bool) -> [ConflictTextView.Highlight] {
        var highlights = [
            ConflictTextView.Highlight(range: conflict.range, color: isCurrent ? .tertiarySystemFill : .quinarySystemFill),
            ConflictTextView.Highlight(range: conflict.ours, color: fill(ours, isCurrent: isCurrent)),
            ConflictTextView.Highlight(range: conflict.theirs, color: fill(theirs, isCurrent: isCurrent)),
        ]
        if let base = conflict.base {
            highlights.append(ConflictTextView.Highlight(range: base, color: fill(Self.base, isCurrent: isCurrent)))
        }
        return highlights
    }
}
