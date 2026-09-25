import Foundation

/// Git wrote something other than the machine-readable format the app asked for.
nonisolated struct UnreadableGitOutput: Error, Equatable {
    let reason: String

    /// Git writes paths as the bytes it stores and everything else as UTF-8. macOS file systems
    /// only hold UTF-8 names, so a path that isn't can't be in the working tree anyway, and failing
    /// the whole read is better than handing back a path Git won't recognize.
    static func text(_ bytes: some Sequence<UInt8>) throws -> String {
        guard let text = String(bytes: bytes, encoding: .utf8) else {
            throw UnreadableGitOutput(reason: "Output is not UTF-8")
        }
        return text
    }
}
