import AppKit
import SwiftUI

/// The review window's comment threads in the diff, and a new one being written. Each thread keeps
/// its view, so a reply being typed survives the diff being read again, and its height at the
/// diff's width, which it reports as it grows.
final class ReviewThreadInserts {
    /// A new thread on lines, or on the file when `lines` is nil.
    struct Draft: Equatable {
        let file: DiffFile.Identity
        let lines: DiffLineTarget?
    }

    private static let draftID = "draft"

    private let session: ReviewSession
    private let diff: DiffViewController
    private var views: [String: NSView] = [:]
    private var heights: [String: (width: Double, height: Double)] = [:]
    private var placements: [UUID: ReviewThreadPlacer.Placement] = [:]
    private var file: DiffFile.Identity?
    private(set) var draft: Draft?
    /// Writes the draft as a thread, given what was typed.
    var submitDraft: ((Draft, String) -> Void)?

    init(session: ReviewSession, diff: DiffViewController) {
        self.session = session
        self.diff = diff
        diff.insertHeight = { [weak self] id, width in self?.height(of: id, at: width) ?? 0 }
        diff.insertView = { [weak self] id in self?.view(for: id) }
    }

    /// The threads of the file shown, where `placements` puts them.
    /// A thread whose place or label changed is shown afresh, and the rest keep their views.
    func show(_ placements: [UUID: ReviewThreadPlacer.Placement], in file: DiffFile.Identity?) {
        if file != self.file {
            draft = nil
            views = [:]
            heights = [:]
        }
        self.file = file
        for id in Array(views.keys) where id != Self.draftID {
            guard let thread = UUID(uuidString: id), let placement = placements[thread], placement == self.placements[thread] else {
                views[id] = nil
                heights[id] = nil
                continue
            }
        }
        self.placements = placements
        updateInserts()
    }

    func startDraft(_ draft: Draft) {
        self.draft = draft
        views[Self.draftID] = nil
        heights[Self.draftID] = nil
        updateInserts()
    }

    func endDraft() {
        draft = nil
        views[Self.draftID] = nil
        heights[Self.draftID] = nil
        updateInserts()
    }

    private func updateInserts() {
        guard let file else {
            diff.inserts = []
            return
        }
        var inserts = placements
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .map { DiffInsert(id: $0.key.uuidString, file: file, place: $0.value.place) }
        if let draft, draft.file == file {
            let place: DiffInsert.Place = draft.lines.map { .line($0.side, $0.lines.upperBound) } ?? .top
            inserts.append(DiffInsert(id: Self.draftID, file: file, place: place))
        }
        diff.inserts = inserts
    }

    private func view(for id: String) -> NSView? {
        if let view = views[id] {
            return view
        }
        let onHeightChange: (CGFloat) -> Void = { [weak self] height in self?.heightChanged(id, to: height) }
        let view: NSView
        if id == Self.draftID {
            guard let draft else { return nil }
            let label = draft.lines.map { ReviewLineAnchor.label($0.lines) } ?? "Comment on File"
            view = NSHostingView(rootView: ReviewDraftView(
                label: label,
                submit: { [weak self] text in self?.submitDraft?(draft, text) },
                cancel: { [weak self] in self?.endDraft() },
                onHeightChange: onHeightChange
            ))
        } else {
            guard let thread = UUID(uuidString: id), let placement = placements[thread] else { return nil }
            view = NSHostingView(rootView: ReviewThreadView(
                session: session,
                threadID: thread,
                label: placement.label,
                isOutdated: placement.isOutdated,
                onHeightChange: onHeightChange
            ))
        }
        views[id] = view
        return view
    }

    /// Measured once at each width, and then as the thread reports it changing.
    private func height(of id: String, at width: Double) -> Double {
        if let known = heights[id], known.width == width {
            return known.height
        }
        guard let view = view(for: id) as? any HeightMeasurable else { return 0 }
        let height = view.height(atWidth: width)
        heights[id] = (width, height)
        return height
    }

    private func heightChanged(_ id: String, to height: CGFloat) {
        guard height > 0, let known = heights[id], abs(known.height - height) >= 0.5 else { return }
        heights[id] = (known.width, height)
        diff.rebuild(keepingPlace: true)
    }
}

/// A hosting view's content measured at a width, before it's been placed.
private protocol HeightMeasurable {
    func height(atWidth width: Double) -> Double
}

extension NSHostingView: HeightMeasurable {
    fileprivate func height(atWidth width: Double) -> Double {
        NSHostingController(rootView: rootView).sizeThatFits(in: NSSize(width: width, height: .greatestFiniteMagnitude)).height
    }
}
