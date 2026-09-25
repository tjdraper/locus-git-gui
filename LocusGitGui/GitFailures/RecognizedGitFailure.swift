import Foundation

/// A failure the app knows the likely cause of and a next step for. Git's messages are matched in
/// English, which `GitEnvironment` makes sure they are.
nonisolated enum RecognizedGitFailure: Equatable, Sendable {
    /// Another Git process holds a lock, or one crashed and left it behind. Covers `index.lock`
    /// and the locks on refs such as `refs/heads/main.lock`.
    case lockExists(URL)
    /// macOS privacy protection kept Git out of the folder. This is the system's wording for EPERM.
    case accessDenied

    static func recognize(_ result: ChildProcess.Result) -> RecognizedGitFailure? {
        guard result.status != 0 else {
            return nil
        }
        let output = (String(bytes: result.standardError, encoding: .utf8) ?? "")
            + (String(bytes: result.standardOutput, encoding: .utf8) ?? "")
        if let match = output.firstMatch(of: #/Unable to create '(?<path>[^']+\.lock)': File exists\./#) {
            return .lockExists(URL(filePath: String(match.output.path)))
        }
        if output.contains("Operation not permitted") {
            return .accessDenied
        }
        return nil
    }
}
