import Foundation

/// Reads `Commit.logCommand`'s output as it arrives, handing back each commit once all its fields
/// have, so a search that finds its matches seconds apart can show each as it's found.
nonisolated struct CommitLogStream {
    private var pending = Data()

    /// Nothing is left over from a commit only partly read.
    var isAtCommitBoundary: Bool {
        pending.isEmpty
    }

    /// Every field ends in a NUL, so a commit is complete once all of its fields' NULs have arrived.
    mutating func read(_ data: Data) throws -> [Commit] {
        pending.append(data)
        var fields = 0
        var end: Data.Index?
        for index in pending.indices where pending[index] == 0 {
            fields += 1
            if fields.isMultiple(of: Commit.fieldCount) {
                end = index
            }
        }
        guard let end else { return [] }
        let complete = pending[...end]
        pending = Data(pending[pending.index(after: end)...])
        return try Commit.parseLog(Data(complete))
    }
}
