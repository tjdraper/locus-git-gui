import Foundation

/// A comment and its replies, on the review as a whole, on a file, or on lines of a file. GitHub's
/// and GitLab's threads have the same shape, so a pull request's can be held here later.
nonisolated struct ReviewThread: Codable, Equatable, Sendable, Identifiable {
    enum Place: Codable, Equatable, Sendable {
        case review
        case file(path: String)
        case lines(ReviewLineAnchor)

        var path: String? {
            switch self {
            case .review: nil
            case let .file(path): path
            case let .lines(anchor): anchor.path
            }
        }
    }

    let id: UUID
    let place: Place
    /// Oldest first. The first starts the thread.
    var comments: [ReviewComment]
    var resolved: Date?

    var isResolved: Bool {
        resolved != nil
    }
}

nonisolated struct ReviewComment: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    /// Markdown.
    var body: String
    let created: Date
    var edited: Date?
}

/// Where a line comment was left. It's followed from there to wherever the lines are now, through
/// the changes made to the file since.
nonisolated struct ReviewLineAnchor: Codable, Equatable, Sendable {
    enum Side: String, Codable, Sendable {
        /// The base side, where removed lines are.
        case old
        case new
    }

    let path: String
    let side: Side
    /// Counted from 1, on that side.
    let lines: ClosedRange<Int>
    /// The file's contents on that side when the comment was left.
    let object: String
    /// The lines as they read then, shown once they've changed.
    let text: [String]
    /// The revision's commits, which a pull request's comment is placed by.
    let base: String?
    let head: String?

    /// Such as "Line 12" or "Lines 12–14".
    static func label(_ lines: ClosedRange<Int>) -> String {
        lines.count == 1 ? "Line \(lines.lowerBound)" : "Lines \(lines.lowerBound)–\(lines.upperBound)"
    }
}
