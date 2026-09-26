import Foundation

/// How many files the working area holds in each group, as its row in the history shows them.
nonisolated struct WorkingAreaSummary: Equatable, Sendable {
    let staged: Int
    let unstaged: Int
    let untracked: Int
    let conflicted: Int

    init(staged: Int = 0, unstaged: Int = 0, untracked: Int = 0, conflicted: Int = 0) {
        self.staged = staged
        self.unstaged = unstaged
        self.untracked = untracked
        self.conflicted = conflicted
    }

    init(_ status: RepositoryStatus) {
        var staged = 0
        var unstaged = 0
        var untracked = 0
        var conflicted = 0
        for file in status.files {
            switch file.state {
            case let .changed(stagedChange, unstagedChange):
                staged += stagedChange == nil ? 0 : 1
                unstaged += unstagedChange == nil ? 0 : 1
            case .untracked:
                untracked += 1
            case .conflicted:
                conflicted += 1
            case .ignored:
                break
            }
        }
        self.init(staged: staged, unstaged: unstaged, untracked: untracked, conflicted: conflicted)
    }

    var isClean: Bool {
        self == WorkingAreaSummary()
    }

    /// Such as “2 staged · 1 unstaged”, leaving out the groups with nothing in them.
    var description: String {
        let parts = [
            conflicted > 0 ? "\(conflicted.formatted()) conflicted" : nil,
            staged > 0 ? "\(staged.formatted()) staged" : nil,
            unstaged > 0 ? "\(unstaged.formatted()) unstaged" : nil,
            untracked > 0 ? "\(untracked.formatted()) untracked" : nil,
        ].compactMap(\.self)
        return parts.isEmpty ? "No changes" : parts.joined(separator: " · ")
    }
}
