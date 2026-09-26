import Foundation

/// A file as the diff view shows it: what changed about it, and its changes as far as they've been
/// read.
nonisolated struct DiffFile: Equatable, Sendable {
    enum Reading: Equatable, Sendable {
        case idle
        /// Reading changes that were left out, after the user asked for them.
        case reading
        case failed(summary: String)
    }

    /// Tells files apart in a diff where the same path can show twice, such as its staged and its
    /// unstaged changes.
    struct Identity: Hashable, Codable, Sendable {
        let group: Int?
        let path: String
    }

    let changed: ChangedFile
    var patch: FilePatch
    var reading = Reading.idle
    /// Which of the diff's groups the file is in, such as staged changes. Nil in a diff that isn't
    /// grouped, such as a commit's.
    let group: Int?

    init(changed: ChangedFile, patch: FilePatch, group: Int? = nil) {
        self.changed = changed
        self.patch = Self.markingChangedWords(in: patch)
        self.group = group
    }

    var id: Identity {
        Identity(group: group, path: changed.path)
    }

    /// Where a line was removed and another added in its place, the words that differ. The removed
    /// lines of a change pair up in order with the added lines that follow them, which is how Git
    /// lays out a line that was edited.
    static func markingChangedWords(in patch: FilePatch) -> FilePatch {
        var patch = patch
        for hunk in patch.hunks.indices {
            for run in changeRuns(in: patch.hunks[hunk].lines) {
                for (old, new) in zip(run.removed, run.added) {
                    guard let ranges = ChangedWords.compare(patch.hunks[hunk].lines[old].text, patch.hunks[hunk].lines[new].text) else {
                        continue
                    }
                    patch.hunks[hunk].lines[old].changedWords = ranges.old
                    patch.hunks[hunk].lines[new].changedWords = ranges.new
                }
            }
        }
        return patch
    }

    /// Each run of changed lines between unchanged ones, split into the indices of its removed and
    /// its added lines.
    static func changeRuns(in lines: [DiffLine]) -> [(removed: [Int], added: [Int])] {
        var runs: [(removed: [Int], added: [Int])] = []
        var removed: [Int] = []
        var added: [Int] = []
        for (index, line) in lines.enumerated() {
            switch line.kind {
            case .context:
                if !removed.isEmpty || !added.isEmpty {
                    runs.append((removed, added))
                    removed = []
                    added = []
                }
            case .removed:
                removed.append(index)
            case .added:
                added.append(index)
            }
        }
        if !removed.isEmpty || !added.isEmpty {
            runs.append((removed, added))
        }
        return runs
    }
}
