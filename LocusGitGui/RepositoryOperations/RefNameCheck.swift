/// What's wrong with a name for a new branch or tag, said before Git refuses it, so the form stays
/// open to fix it. Git's rules are in `git check-ref-format`; these are the ones people run into.
nonisolated enum RefNameCheck {
    /// `kind` is “branch” or “tag”. Nil when the name is fine or still empty.
    static func problem(with name: String, kind: String, taken: Set<String>) -> String? {
        guard !name.isEmpty else { return nil }
        if taken.contains(name) {
            return "There’s already a \(kind) named “\(name)”."
        }
        if name.contains(where: { $0.isWhitespace || $0.isNewline }) {
            return "A \(kind)’s name can’t have spaces in it."
        }
        if name.contains(where: { "~^:?*[\\".contains($0) }) || name.contains("..") || name.contains("@{") || name.contains("//") {
            return "A \(kind)’s name can’t have ~ ^ : ? * [ \\ .. @{ or // in it."
        }
        if name.hasPrefix("-") || name.hasPrefix("/") || name.hasPrefix(".") || name.hasSuffix("/") || name.hasSuffix(".")
            || name.hasSuffix(".lock") || name == "@" || name.contains("/.") {
            return "A \(kind)’s name can’t start with - / or ., or end with / . or .lock."
        }
        return nil
    }
}
