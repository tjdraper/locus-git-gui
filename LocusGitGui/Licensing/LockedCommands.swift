/// Which commands are locked after the trial. The palette refuses them as they're chosen, before
/// asking which branch or stash, and each flow they lead to asks `ReadOnlyLock` as it starts, since
/// buttons, drags and double-clicks reach the same flows without a command.
nonisolated extension AppCommand {
    /// Changes a repository, makes one, or talks to a remote. A display name and pins are left out:
    /// they change how the app shows a repository rather than the work in it. So is saving a
    /// resolved conflict, which writes only what was typed, and typing is what's locked.
    var changesRepository: Bool {
        switch self {
        case .cloneRepository, .createRepository,
             .checkOutBranch, .newBranch, .renameBranch, .deleteBranch, .setUpstream, .unsetUpstream,
             .mergeIntoCurrentBranch, .rebaseCurrentBranch, .newTag, .deleteTag,
             .continueOperation, .skipCommit, .abortOperation, .takeOurs, .takeTheirs, .takeBoth, .markConflictResolved,
             .commitChanges, .toggleFileStaging, .toggleHunkStaging, .discardFile, .discardHunk, .stageAll, .unstageAll,
             .checkOutCommit, .newBranchFromCommit, .newTagOnCommit, .cherryPickCommit, .revertCommit,
             .softResetToCommit, .mixedResetToCommit, .hardResetToCommit, .rewordCommit, .editCommit,
             .stashChanges, .stashIncludingUntracked, .applyStash, .popStash, .dropStash,
             .fetch, .fetchWithoutOptions, .fetchAndPrune, .fetchWithTags, .pull, .push, .forcePush,
             .addRemote, .fetchFromRemote, .editRemote, .removeRemote, .pushTag, .deleteRemoteTag, .deleteRemoteBranch:
            true
        default:
            false
        }
    }
}
