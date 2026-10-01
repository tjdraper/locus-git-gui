import AppKit
import os

/// Comments in the review window: on lines picked in the diff, and on the file shown, each placed
/// where its lines are now.
extension ReviewWindowController {
    private static let commentLog = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "Reviews")

    func connectComments() {
        diff.lineActions = { [weak self] target in
            guard let self else { return [] }
            return [DiffAction(title: "Comment on \(ReviewLineAnchor.label(target.lines))") { [weak self] in
                self?.threads.startDraft(ReviewThreadInserts.Draft(file: target.file, lines: target))
            }]
        }
        threads.submitDraft = { [weak self] draft, text in self?.submit(draft, text: text) }
        diff.lineButtons.action = DiffLineButton(symbol: "plus.bubble.fill", title: "Comment on This Line") { [weak self] target in
            self?.threads.startDraft(ReviewThreadInserts.Draft(file: target.file, lines: target))
        }
        followThreads()
    }

    /// A comment on the lines selected, or else on the file shown.
    func startComment() {
        guard let shown else { return }
        let file = DiffFile.Identity(group: nil, path: shown.entry.file.path)
        threads.startDraft(ReviewThreadInserts.Draft(file: file, lines: diff.selectedLineTarget))
    }

    /// Shows the review's comments with the field for a new one ready.
    func startReviewComment() {
        session.selection = [ReviewSession.overviewTag]
        session.reviewCommentRequest += 1
    }

    func startFileComment(_ path: String) {
        threads.startDraft(ReviewThreadInserts.Draft(file: DiffFile.Identity(group: nil, path: path), lines: nil))
    }

    /// Placed again whenever the review's threads change.
    private func followThreads() {
        withObservationTracking {
            _ = session.review?.threads
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.placeThreads()
                self?.followThreads()
            }
        }
    }

    func placeThreads() {
        guard let shown, let threads = session.review?.threads else { return }
        let file = shown.entry.file
        guard threads.contains(where: { $0.place.path == file.path || ($0.place.path != nil && $0.place.path == file.originalPath) }) else {
            self.threads.show([:], in: DiffFile.Identity(group: nil, path: file.path))
            return
        }
        Task { [weak self] in
            guard let self, let sides = try? await sides(of: shown.entry, sinceReviewed: shown.sinceReviewed) else { return }
            let placements = await ReviewThreadPlacer(session: session).place(threads, in: shown.entry.file, sides: sides)
            guard self.shown?.entry.file == shown.entry.file else { return }
            self.threads.show(placements, in: DiffFile.Identity(group: nil, path: shown.entry.file.path))
        }
    }

    /// The contents each side of the diff shows. A file in the working tree is stored first, so
    /// lines can be followed to it.
    private func sides(of entry: ReviewSession.Entry, sinceReviewed: Bool) async throws -> ReviewThreadPlacer.Sides {
        let review = session.review
        let isWorkingTree = review?.revision?.includesWorkingTree == true && entry.file.newObject != nil
        let current = isWorkingTree ? try await session.storeWorkingTreeFile(entry.file.path) : entry.file.newObject
        guard sinceReviewed, let reviewed = review?.checks.reviewedVersion(of: entry.file.path)?.newObject else {
            return ReviewThreadPlacer.Sides(old: entry.file.oldObject, new: current)
        }
        return ReviewThreadPlacer.Sides(old: reviewed, new: current)
    }

    private func submit(_ draft: ReviewThreadInserts.Draft, text: String) {
        guard let shown, let revision = session.review?.revision else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lines = draft.lines else {
            session.startThread(.file(path: draft.file.path), body: body)
            threads.endDraft()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let sides = try await sides(of: shown.entry, sinceReviewed: shown.sinceReviewed)
                guard let object = lines.side == .old ? sides.old : sides.new else { return }
                let file = shown.entry.file
                let anchor = ReviewLineAnchor(
                    path: lines.side == .old ? file.originalPath ?? file.path : file.path,
                    side: lines.side == .old ? .old : .new,
                    lines: lines.lines,
                    object: object,
                    text: lines.text,
                    base: revision.comparedBase,
                    head: revision.comparedHead
                )
                session.startThread(.lines(anchor), body: body)
                threads.endDraft()
            } catch {
                Self.commentLog.error("Leaving a comment failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }
}
