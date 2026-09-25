import Foundation

/// A command as someone would type it in Terminal, so it can be pasted there to try again.
nonisolated enum GitCommandLine {
    static func display(_ arguments: [String]) -> String {
        (["git"] + arguments.map(quoted)).joined(separator: " ")
    }

    private static func quoted(_ argument: String) -> String {
        let needsNoQuotes = !argument.isEmpty
            && argument.allSatisfy { $0.isLetter || $0.isNumber || "-_=./:@%+,".contains($0) }
        if needsNoQuotes {
            return argument
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
