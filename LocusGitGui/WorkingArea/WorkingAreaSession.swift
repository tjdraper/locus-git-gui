/// What a repository's working area views share, the detail column's and the working area window's:
/// the message being written, and the queue their commands take turns in, so a commit made in one
/// waits for staging done in the other.
final class WorkingAreaSession {
    let editor = CommitMessageEditor()
    let queue = WorkingAreaCommandQueue()
    let committing: CommitWorkflow

    init(commands: RepositoryCommandRunner, draft: CommitMessage?) {
        editor.message = draft ?? CommitMessage()
        committing = CommitWorkflow(commands: commands, editor: editor, queue: queue)
    }
}
