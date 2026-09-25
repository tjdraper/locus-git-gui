/// The environment one Git command runs with: the user's own, plus what the app needs to read
/// Git reliably.
nonisolated enum GitEnvironment {
    /// Every locale category `LC_ALL` overrides, except messages.
    private static let nonMessageCategories = ["LC_CTYPE", "LC_COLLATE", "LC_NUMERIC", "LC_TIME", "LC_MONETARY"]

    static func variables(for command: GitCommand, from base: [String: String]) -> [String: String] {
        var variables = withEnglishMessages(base)
        if command.isReadOnly {
            // Otherwise `status` refreshes the index and takes `index.lock` to do it, which makes a
            // command the user runs in Terminal at the same moment fail.
            variables["GIT_OPTIONAL_LOCKS"] = "0"
        }
        return variables
    }

    /// The app recognizes failures by Git's English wording. Only messages change, so file names
    /// and commit messages outside ASCII still come through in the user's own encoding.
    ///
    /// `LC_ALL` overrides `LC_MESSAGES`, so it is spread over the other categories instead. gettext
    /// ignores `LANGUAGE` once messages are in the C locale, so it can stay.
    static func withEnglishMessages(_ base: [String: String]) -> [String: String] {
        var variables = base
        if let all = variables.removeValue(forKey: "LC_ALL"), !all.isEmpty {
            for category in nonMessageCategories {
                variables[category] = all
            }
        }
        variables["LC_MESSAGES"] = "C"
        return variables
    }
}
