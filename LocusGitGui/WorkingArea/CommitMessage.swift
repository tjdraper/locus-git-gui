import Foundation

/// A commit message as the working area edits it: the subject and the body apart, joined by a blank
/// line when committed, as Git expects.
nonisolated struct CommitMessage: Codable, Equatable, Sendable {
    var subject = ""
    var body = ""

    init(subject: String = "", body: String = "") {
        self.subject = subject
        self.body = body
    }

    /// The first line is the subject and the rest is the body, with the blank line between them
    /// dropped.
    init(parsing message: String) {
        let lines = message.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        subject = lines.first.map(String.init) ?? ""
        body = lines.count > 1 ? lines[1].trimmingCharacters(in: .newlines) : ""
    }

    var isEmpty: Bool {
        subject.trimmingCharacters(in: .whitespaces).isEmpty && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A commit needs a subject.
    var canCommit: Bool {
        !subject.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Git tidies the rest, such as trailing spaces. The body's first line keeps its indent, which
    /// can be the start of an example.
    var text: String {
        let subject = subject.trimmingCharacters(in: .whitespaces)
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return subject }
        return "\(subject)\n\n\(body.trimmingCharacters(in: .newlines))"
    }
}
