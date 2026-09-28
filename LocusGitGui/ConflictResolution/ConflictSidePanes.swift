import AppKit

/// The panes above the result, showing each version of the file whole: the checked-out side, the
/// side being brought in, and the common ancestor when it's shown. Each marks where every conflict's
/// side is in it, the current one more strongly, and follows the result's current conflict. Each
/// version's lines are indexed away from the main actor, which for a file of hundreds of thousands
/// of lines takes a moment, and the marks follow once they are.
final class ConflictSidePanes {
    let ours = ConflictTextPane(color: ConflictColors.ours, isEditable: false)
    let base = ConflictTextPane(color: ConflictColors.base, isEditable: false)
    let theirs = ConflictTextPane(color: ConflictColors.theirs, isEditable: false)
    private var locators: [ConflictSideLocator.Side: ConflictSideLocator] = [:]
    private var located: [ConflictSideLocator.Side: [Range<Int>?]] = [:]
    private var shownCurrent: Int?
    private var indexing: Task<Void, Never>?
    /// The result's conflicts as last found, to locate once the versions are indexed.
    private var lastFound: (markers: ConflictMarkers, result: String)?

    private static let sides: [ConflictSideLocator.Side] = [.ours, .theirs, .base]

    private func pane(_ side: ConflictSideLocator.Side) -> ConflictTextPane {
        switch side {
        case .ours: ours
        case .theirs: theirs
        case .base: base
        }
    }

    private static func color(_ side: ConflictSideLocator.Side) -> NSColor {
        switch side {
        case .ours: ConflictColors.ours
        case .theirs: ConflictColors.theirs
        case .base: ConflictColors.base
        }
    }

    func load(_ contents: ConflictFileContents, names: ConflictSideNames) {
        ours.setTitle(names.ours)
        theirs.setTitle(names.theirs)
        base.setTitle("Base", detail: contents.base == .absent ? "Added on both sides" : "")
        locators = [:]
        located = [:]
        shownCurrent = nil
        lastFound = nil
        var texts: [ConflictSideLocator.Side: String] = [:]
        for side in Self.sides {
            let version = switch side {
            case .ours: contents.ours
            case .theirs: contents.theirs
            case .base: contents.base
            }
            let text = version.text ?? ""
            pane(side).setText(text)
            pane(side).textView.highlights = []
            texts[side] = text
        }
        indexing?.cancel()
        indexing = Task { [weak self] in
            let locators = await Self.index(texts)
            guard !Task.isCancelled, let self else { return }
            self.locators = locators
            if let lastFound {
                locate(lastFound.markers, in: lastFound.result, current: shownCurrent)
            }
        }
    }

    @concurrent
    private static func index(_ texts: [ConflictSideLocator.Side: String]) async -> [ConflictSideLocator.Side: ConflictSideLocator] {
        texts.mapValues { ConflictSideLocator(file: $0) }
    }

    /// Where each conflict is in each version, found again after the result's conflicts are.
    func locate(_ markers: ConflictMarkers, in result: String, current: Int?) {
        lastFound = (markers, result)
        guard !locators.isEmpty else {
            shownCurrent = current
            return
        }
        for (side, locator) in locators {
            located[side] = locator.locate(side, of: markers, in: result)
        }
        shownCurrent = nil
        show(current: current)
    }

    /// Marks the current conflict more strongly, and scrolls each version to it when it's another one.
    func show(current: Int?) {
        let isNewConflict = current != shownCurrent
        shownCurrent = current
        for side in Self.sides {
            guard let locator = locators[side], let ranges = located[side] else { continue }
            let textView = pane(side).textView
            textView.highlights = ranges.enumerated().compactMap { index, lines in
                lines.map {
                    ConflictTextView.Highlight(
                        range: locator.characters(of: $0),
                        color: ConflictColors.fill(Self.color(side), isCurrent: index == current)
                    )
                }
            }
            if isNewConflict {
                scroll(side, to: current)
            }
        }
    }

    /// After the panes change width, which wraps their lines again and moves the conflict.
    func scrollToCurrent() {
        for side in Self.sides {
            scroll(side, to: shownCurrent)
        }
    }

    private func scroll(_ side: ConflictSideLocator.Side, to conflict: Int?) {
        guard let conflict, let locator = locators[side], let ranges = located[side], ranges.indices.contains(conflict),
              let lines = ranges[conflict]
        else { return }
        pane(side).textView.scrollToMiddle(locator.characters(of: lines))
    }
}
