/// What a failed fetch, pull or push offers beyond trying again, each shown only for the failure it
/// answers: Pull or Force Push for a push the remote is ahead of, Fetch for a force push that found
/// the remote had moved, Push for a pull whose upstream was deleted.
struct GitFailureNextSteps {
    var pull: (() -> Void)?
    var push: (() -> Void)?
    var forcePush: (() -> Void)?
    var fetch: (() -> Void)?
}
