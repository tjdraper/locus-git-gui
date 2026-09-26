import AppKit

/// The message being written in the working area, whether it amends the last commit, and whether
/// there's anything to commit.
@Observable
final class CommitMessageEditor {
    /// What the working area knows about the repository as of its last refresh.
    struct Repository: Equatable {
        var staged = 0
        var conflicts = 0
        var hasChanges = false
        var hasCommits = false
        /// A merge commits whatever is staged, even when that matches the last commit.
        var isMerging = false
        /// Where the last commit already is, which amending it rewrites.
        var pushedTo: String?
    }

    /// The commit an amend rewrites.
    struct AmendedCommit: Equatable {
        let hash: String
        let subject: String
    }

    var message = CommitMessage() {
        didSet {
            guard message != oldValue, amendedCommit == nil else { return }
            onDraftChange?(message)
        }
    }

    var repository = Repository()
    var isCommitting = false
    /// Reading the last commit's message for an amend.
    var isLoadingAmend = false
    /// Nil unless amending.
    private(set) var amendedCommit: AmendedCommit?
    /// Fields that show the message, told when it changes from outside them, such as when an amend
    /// loads the last commit's message.
    private(set) var externalChanges = 0

    @ObservationIgnored var onDraftChange: ((CommitMessage) -> Void)?
    @ObservationIgnored var commit: (() -> Void)?
    @ObservationIgnored var toggleAmend: (() -> Void)?
    @ObservationIgnored weak var subjectField: NSTextField?
    @ObservationIgnored weak var bodyTextView: NSTextView?
    /// What was being written before an amend replaced it, put back when the amend is turned off.
    @ObservationIgnored private var draftBeforeAmend: CommitMessage?

    var isAmending: Bool {
        amendedCommit != nil
    }

    /// Git won't amend while a merge is waiting for its commit.
    var canAmend: Bool {
        repository.hasCommits && !repository.isMerging && !isCommitting && !isLoadingAmend
    }

    /// What's kept for the next commit: the message being written, or while amending, the one set
    /// aside for it.
    var draft: CommitMessage? {
        let draft = isAmending ? draftBeforeAmend : message
        return draft?.isEmpty == false ? draft : nil
    }

    var canCommit: Bool {
        hint == nil && !isCommitting
    }

    var commitTitle: String {
        isAmending ? "Amend Commit" : "Commit"
    }

    /// Why Commit is disabled, when it is.
    var hint: String? {
        if repository.conflicts > 0 {
            return "Resolve the conflicts to commit."
        }
        if repository.staged == 0, !isAmending, !repository.isMerging {
            return repository.hasChanges ? "Stage the changes to commit." : "No changes to commit."
        }
        if !message.canCommit {
            return "Write a subject to commit."
        }
        return nil
    }

    /// What an amend will change, and a warning when the commit has already been pushed.
    var amendNote: String? {
        guard let amendedCommit else { return nil }
        let subject = amendedCommit.subject.isEmpty ? String(amendedCommit.hash.prefix(7)) : "“\(amendedCommit.subject)”"
        let change = repository.staged > 0
            ? "The staged changes are added to it, and its message is replaced."
            : "Only its message changes."
        let pushed = repository.pushedTo.map { " It’s already on \($0), so pushing it again will need a force push." } ?? ""
        return "Amending \(subject). \(change)\(pushed)"
    }

    func beginAmending(_ commit: AmendedCommit, message: CommitMessage) {
        draftBeforeAmend = self.message
        amendedCommit = commit
        replaceMessage(with: message)
    }

    func stopAmending() {
        guard amendedCommit != nil else { return }
        amendedCommit = nil
        replaceMessage(with: draftBeforeAmend ?? CommitMessage())
        draftBeforeAmend = nil
    }

    /// Once the commit is made, its message is done with. After an amend, what was being written
    /// before it comes back.
    func finishCommitting() {
        amendedCommit = nil
        replaceMessage(with: draftBeforeAmend ?? CommitMessage())
        draftBeforeAmend = nil
    }

    /// When the message was changed while the amend ran, it's the start of the next one, and stays.
    func finishAmendingKeepingMessage() {
        amendedCommit = nil
        draftBeforeAmend = nil
        onDraftChange?(message)
    }

    func replaceMessage(with message: CommitMessage) {
        self.message = message
        externalChanges += 1
    }

    func focusSubject() {
        guard let subjectField else { return }
        subjectField.window?.makeFirstResponder(subjectField)
    }

    func focusBody() {
        guard let bodyTextView else { return }
        bodyTextView.window?.makeFirstResponder(bodyTextView)
    }
}
