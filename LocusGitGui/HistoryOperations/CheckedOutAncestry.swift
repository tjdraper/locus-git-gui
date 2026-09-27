/// Whether commits are in the checked-out branch's history, which rewording or editing one needs,
/// since that rewrites the branch. Menus ask while they open, so the answer is looked up ahead, when
/// a commit is selected, and kept until the branch moves.
final class CheckedOutAncestry {
    private let run: (GitCommand) async throws -> ChildProcess.Result
    /// The checked-out commit the answers are for.
    private var head: String?
    private var answers: [String: Bool] = [:]
    private var asking: Set<String> = []

    init(run: @escaping (GitCommand) async throws -> ChildProcess.Result) {
        self.run = run
    }

    /// After each refresh. The answers only hold for the commit they were worked out from.
    func show(head: String?) {
        guard head != self.head else { return }
        self.head = head
        answers = [:]
    }

    /// Nil until it's been looked up, which this starts.
    func isOnCheckedOutBranch(_ commit: String) -> Bool? {
        if let answer = answers[commit] {
            return answer
        }
        lookUp(commit)
        return nil
    }

    func lookUp(_ commit: String) {
        guard let head, answers[commit] == nil, !asking.contains(commit) else { return }
        asking.insert(commit)
        Task { [weak self, run] in
            let result = try? await run(HistoryOperationCommand.isAncestor(commit, of: head))
            guard let self else { return }
            asking.remove(commit)
            guard self.head == head, let result else { return }
            answers[commit] = result.status == 0
        }
    }
}
