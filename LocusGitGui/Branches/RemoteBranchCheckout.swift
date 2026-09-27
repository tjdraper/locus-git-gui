/// What checking out a remote branch does: switch to the local branch that already tracks it,
/// found by its upstream rather than its name, or make one of the same name that tracks it. A
/// local branch of that name tracking something else isn't taken over, so the user picks another.
nonisolated enum RemoteBranchCheckout: Equatable, Sendable {
    case switchTo(branch: String)
    case create(name: String)
    case askForName(suggested: String)

    /// `remoteBranch` is the full name, such as `refs/remotes/origin/feature`, and `nameOnRemote`
    /// the branch's name there, such as `feature`.
    static func plan(remoteBranch: String, remote: String, nameOnRemote: String, refs: [Ref]) -> RemoteBranchCheckout {
        let locals = refs.filter { $0.kind == .localBranch }
        let tracking = locals
            .filter { $0.upstream == remoteBranch }
            .map { String($0.name.dropFirst("refs/heads/".count)) }
        // The one of the same name first, when several track it.
        if let branch = tracking.first(where: { $0 == nameOnRemote }) ?? tracking.first {
            return .switchTo(branch: branch)
        }
        let taken = Set(locals.map { String($0.name.dropFirst("refs/heads/".count)) })
        guard taken.contains(nameOnRemote) else {
            return .create(name: nameOnRemote)
        }
        var suggested = "\(remote)-\(nameOnRemote)"
        var number = 2
        while taken.contains(suggested) {
            suggested = "\(remote)-\(nameOnRemote)-\(number)"
            number += 1
        }
        return .askForName(suggested: suggested)
    }
}
