/// Git's output as a terminal would show it. Progress rewrites its line with a carriage return, a
/// hundred times over for a large fetch, and pads it with spaces to cover a longer line before it.
nonisolated enum TerminalOutput {
    static func rendered(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let shown = line.split(separator: "\r").last { !$0.allSatisfy(\.isWhitespace) } ?? ""
                return String(shown.reversed().drop { $0 == " " }.reversed())
            }
            .joined(separator: "\n")
    }
}
