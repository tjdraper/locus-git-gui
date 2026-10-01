import Foundation

/// Follows lines a comment was left on through the changes made to their file since, as GitLab
/// does: lines moved by changes elsewhere move with them, and a change to the lines themselves
/// leaves the comment outdated.
nonisolated enum ReviewAnchorFollowing {
    /// Every hunk with no lines around it, so each says exactly which lines it changed.
    static func changesCommand(from old: String, to new: String) -> GitCommand {
        .reading(["diff", "--patch", "--no-color", "--no-ext-diff", "--no-textconv", "--unified=0", "--end-of-options", old, new])
    }

    /// Nil when a hunk changed any of the lines, or added lines between them. `hunks` are from
    /// `changesCommand`.
    static func follow(_ lines: ClosedRange<Int>, through hunks: [DiffHunk]) -> ClosedRange<Int>? {
        var shift = 0
        for hunk in hunks {
            let removed = hunk.lines.count { $0.kind == .removed }
            let added = hunk.lines.count { $0.kind == .added }
            if removed == 0 {
                // Git numbers a pure addition by the old line it follows.
                if hunk.oldStart < lines.lowerBound {
                    shift += added
                } else if hunk.oldStart < lines.upperBound {
                    return nil
                }
                continue
            }
            let changed = hunk.oldStart ... hunk.oldStart + removed - 1
            if changed.upperBound < lines.lowerBound {
                shift += added - removed
            } else if changed.overlaps(lines) {
                return nil
            }
        }
        return lines.lowerBound + shift ... lines.upperBound + shift
    }
}
