/// What a failed command offers beyond trying again, each shown only for the failure it answers:
/// Pull or Force Push for a push the remote is ahead of, Fetch for a force push that found the
/// remote had moved, Push for a pull whose upstream was deleted, Stash and Continue for local
/// changes in the way, Delete Anyway for a branch that isn't merged, and Show Conflicts for an
/// operation that stopped on them.
struct GitFailureNextSteps {
    var pull: (() -> Void)?
    var push: (() -> Void)?
    var forcePush: (() -> Void)?
    var fetch: (() -> Void)?
    var stashAndContinue: (() -> Void)?
    var deleteAnyway: (() -> Void)?
    var showConflicts: (() -> Void)?
}
