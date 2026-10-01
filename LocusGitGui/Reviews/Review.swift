import Foundation

/// What differs between two points in a repository, checked off file by file, with comments on it,
/// its files and their lines. Plain data, kept apart from the windows that show it, so a pull
/// request's review can be held the same way later.
nonisolated struct Review: Codable, Equatable, Sendable, Identifiable {
    /// Every review is local until pull requests are connected.
    enum Origin: Codable, Equatable, Sendable {
        case local
    }

    /// How far through the review is, as of the last time its files were read, so the list can say
    /// without reading every review's files again.
    struct Progress: Codable, Equatable, Sendable {
        var files = 0
        var checked = 0
        var changedSinceReviewed = 0

        /// A review with nothing to check isn't done, since there was nothing to review.
        var isDone: Bool {
            files > 0 && checked == files
        }
    }

    let id: UUID
    /// Nil until renamed, so the review is named for its points as they change.
    var name: String?
    var origin: Origin
    var base: ReviewPoint
    var head: ReviewPoint
    let created: Date
    var lastOpened: Date
    /// A check, a comment, a rename or a new revision. Opening the review isn't one.
    var lastChanged: Date
    /// Oldest first.
    var revisions: [ReviewRevision]
    var checks: ReviewChecks
    var threads: [ReviewThread]
    var progress: Progress
    /// A followed point that no longer resolves, such as a branch deleted after its pull request
    /// was merged. The review stays where it last was.
    var missingPoints: Set<ReviewPoint>

    init(id: UUID = UUID(), name: String? = nil, base: ReviewPoint, head: ReviewPoint, created: Date) {
        self.id = id
        self.name = name
        origin = .local
        self.base = base
        self.head = head
        self.created = created
        lastOpened = created
        lastChanged = created
        revisions = []
        checks = ReviewChecks()
        threads = []
        progress = Progress()
        missingPoints = []
    }

    var title: String {
        name ?? comparison
    }

    /// Such as "feature → production".
    var comparison: String {
        "\(head.title) → \(base.title)"
    }

    var revision: ReviewRevision? {
        revisions.last
    }

    var unresolvedThreads: Int {
        threads.count { !$0.isResolved }
    }

    /// Every object the repository has to keep so the review's checks and comments still work
    /// after a force push or a rebase.
    var keptObjects: Set<String> {
        var objects = checks.keptObjects
        for thread in threads {
            if case let .lines(anchor) = thread.place {
                objects.insert(anchor.object)
            }
        }
        return objects
    }
}
