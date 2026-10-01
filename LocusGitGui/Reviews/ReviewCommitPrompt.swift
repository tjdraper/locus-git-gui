import AppKit

/// Asks for a commit to compare, by anything Git takes as one: a hash, a ref, or `HEAD~3`.
enum ReviewCommitPrompt {
    static func verifyCommand(_ revision: String) -> GitCommand {
        .reading(["rev-parse", "--verify", "--quiet", "--end-of-options", revision + "^{commit}"])
    }

    /// Asks again, saying so, until what's typed names a commit or the prompt is cancelled.
    static func ask(on window: NSWindow?, commands: RepositoryCommandRunner) async -> String? {
        var problem: String?
        var typed = ""
        while true {
            let alert = NSAlert()
            alert.messageText = "Compare a commit"
            alert.informativeText = problem ?? "Type a commit’s hash, or anything else Git takes as a commit, such as “HEAD~3”."
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            field.stringValue = typed
            field.placeholderString = "Commit"
            alert.accessoryView = field
            alert.addButton(withTitle: "Compare")
            alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
            alert.window.initialFirstResponder = field
            guard await AlertPresentation.run(alert, on: window) == .alertFirstButtonReturn else {
                return nil
            }
            typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !typed.isEmpty else { continue }
            if let result = try? await commands.run(verifyCommand(typed)), result.status == 0,
               let hash = String(bytes: result.standardOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !hash.isEmpty {
                return hash
            }
            problem = "“\(typed)” isn’t a commit in this repository."
        }
    }
}
