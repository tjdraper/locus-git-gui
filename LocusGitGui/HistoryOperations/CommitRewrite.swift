/// Rewording or editing one commit on the checked-out branch, as a small interactive rebase that
/// marks that commit `edit` and picks the rest as they are. Git stops at the commit: an edit waits
/// there for the user, and a reword amends the message and carries on.
nonisolated enum CommitRewrite {
    /// Rewrites the todo list Git hands the sequence editor, turning the commit's `pick` into
    /// `edit`. The list names commits by abbreviated hash, so a line is the commit's when its hash
    /// starts the full one. Run by Git through the shell, with the list's path as its argument.
    static func sequenceEditor(marking commit: String) -> String {
        let program = #"{ if (($1 == "pick" || $1 == "p") && length($2) >= 4 && index(h, $2) == 1) { sub(/^(pick|p) /, "edit ") } print }"#
        return #"f() { /usr/bin/awk -v h=\#(commit) '\#(program)' "$1" > "$1.locus" && mv "$1.locus" "$1"; }; f"#
    }

    /// Merges after the commit are made again rather than flattened, and fixup commits aren't
    /// folded in, whatever the user's configuration says. `parent` is nil for the first commit.
    static func start(marking commit: String, parent: String?, autostash: Bool = false) -> GitCommand {
        var arguments = ["-c", "rebase.abbreviateCommands=false", "rebase", "--interactive", "--rebase-merges", "--no-autosquash"]
        if autostash {
            arguments.append("--autostash")
        }
        arguments.append(parent ?? "--root")
        var command = GitCommand.changing(arguments)
        command.environment = HistoryOperationCommand.keepMessage.merging(["GIT_SEQUENCE_EDITOR": sequenceEditor(marking: commit)]) { $1 }
        return command
    }

    /// The new message for the commit the rebase stopped at, leaving anything staged out of it.
    static func reword(message: String) -> GitCommand {
        .changing(["commit", "--amend", "--only", "--allow-empty", "--message=" + message])
    }
}
