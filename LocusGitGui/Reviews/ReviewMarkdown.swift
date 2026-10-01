import Foundation

/// A review's unresolved comments as Markdown, to paste into a pull request, an issue or a
/// message, since comments are otherwise kept on this Mac only.
nonisolated enum ReviewMarkdown {
    /// Comments on the review first, then each file's in path order, each thread's lines in order.
    static func unresolvedComments(of review: Review) -> String {
        let threads = review.threads.filter { !$0.isResolved }
        var sections = ["# \(review.title)"]
        let general = threads.filter { $0.place == .review }
        if !general.isEmpty {
            sections.append("## The Review")
            sections += general.map(thread)
        }
        let byPath = Dictionary(grouping: threads.filter { $0.place.path != nil }) { $0.place.path ?? "" }
        for path in byPath.keys.sorted() {
            sections.append("## `\(path)`")
            let ordered = (byPath[path] ?? []).sorted { firstLine(of: $0) < firstLine(of: $1) }
            sections += ordered.map(thread)
        }
        return sections.joined(separator: "\n\n") + "\n"
    }

    private static func firstLine(of thread: ReviewThread) -> Int {
        if case let .lines(anchor) = thread.place {
            return anchor.lines.lowerBound
        }
        return 0
    }

    private static func thread(_ thread: ReviewThread) -> String {
        var parts: [String] = []
        if case let .lines(anchor) = thread.place {
            let side = anchor.side == .old ? " (removed)" : ""
            parts.append("**\(ReviewLineAnchor.label(anchor.lines))\(side)**")
            let fence = anchor.text.contains { $0.contains("```") } ? "~~~" : "```"
            parts.append(([fence] + anchor.text + [fence]).joined(separator: "\n"))
        }
        for (index, comment) in thread.comments.enumerated() {
            parts.append(index == 0 ? comment.body : "**Reply:** \(comment.body)")
        }
        return parts.joined(separator: "\n\n")
    }
}
