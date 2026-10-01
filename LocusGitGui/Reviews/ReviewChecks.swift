import Foundation

/// Which of a review's files have been checked off, each as it was when checked.
nonisolated struct ReviewChecks: Codable, Equatable, Sendable {
    struct Check: Codable, Equatable, Sendable {
        let file: ReviewedFile
        let date: Date
    }

    enum State: Equatable, Sendable {
        case unchecked
        case checked
        /// Checked, then changed by a later revision, which cleared the check.
        case changedSinceReviewed
    }

    /// By path.
    private(set) var checked: [String: Check] = [:]
    /// Checks a change cleared, kept so the file can show only what changed since.
    private(set) var cleared: [String: Check] = [:]

    func state(of file: ReviewedFile) -> State {
        if checked[file.path]?.file == file {
            .checked
        } else if cleared[file.path] != nil {
            .changedSinceReviewed
        } else {
            .unchecked
        }
    }

    /// The file as it was when last checked, for a file changed since.
    func reviewedVersion(of path: String) -> ReviewedFile? {
        cleared[path]?.file
    }

    mutating func check(_ file: ReviewedFile, at date: Date) {
        checked[file.path] = Check(file: file, date: date)
        cleared[file.path] = nil
    }

    /// Unchecked by hand, so there's no earlier review to show changes since.
    mutating func uncheck(_ path: String) {
        checked[path] = nil
        cleared[path] = nil
    }

    /// Brings the checks up to date with the review's files as they are now. A checked file that
    /// changed has its check cleared, one changed back to how it was checked has it again, and a
    /// file no longer in the review takes its check with it. Returns whether anything changed.
    @discardableResult
    mutating func follow(_ files: [ReviewedFile]) -> Bool {
        let before = self
        let current = Dictionary(files.map { ($0.path, $0) }) { first, _ in first }
        for (path, check) in checked {
            if let file = current[path] {
                if file != check.file {
                    checked[path] = nil
                    cleared[path] = check
                }
            } else {
                checked[path] = nil
            }
        }
        for (path, check) in cleared {
            if let file = current[path] {
                if file == check.file {
                    cleared[path] = nil
                    checked[path] = check
                }
            } else {
                cleared[path] = nil
            }
        }
        return self != before
    }

    /// Every object a check refers to, which the repository has to keep for the review.
    var keptObjects: Set<String> {
        Set((checked.values.map(\.file) + cleared.values.map(\.file)).flatMap(\.keptObjects))
    }
}
