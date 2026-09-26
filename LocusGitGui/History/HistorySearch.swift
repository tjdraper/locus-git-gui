import Foundation

/// What Find in History looks for, and where.
nonisolated struct HistorySearch: Equatable, Sendable {
    enum Field: String, CaseIterable, Sendable {
        /// A commit's message, or its hash typed in full or in part.
        case message
        case author
        /// Commits that add or remove the text, as `git log -S` finds them.
        case changes
    }

    /// The shortest hash Git will look up.
    private static let shortestHash = 4
    /// A SHA-256 hash, the longest Git has.
    private static let longestHash = 64

    let text: String
    let field: Field

    /// Nil when there's nothing to look for.
    init?(text: String, field: Field) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        self.text = text
        self.field = field
    }

    /// Ignoring case, and taking the text as typed rather than as a pattern. `-S` ignores
    /// `--fixed-strings` and always takes the text as typed.
    var logArguments: [String] {
        switch field {
        case .message: ["--regexp-ignore-case", "--fixed-strings", "--grep=" + text]
        case .author: ["--regexp-ignore-case", "--fixed-strings", "--author=" + text]
        case .changes: ["-S" + text]
        }
    }

    /// Git can't search hashes and messages in one command, so something that could be a hash is
    /// also looked up by itself.
    var hashCandidate: String? {
        guard field == .message,
              (Self.shortestHash ... Self.longestHash).contains(text.count),
              text.allSatisfy(\.isHexDigit)
        else { return nil }
        return text
    }
}
