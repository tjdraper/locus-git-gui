import Foundation

/// A conflicted file's versions as the index holds them while a merge waits on it: the common
/// ancestor, the checked-out side and the side being brought in, which Git numbers stages 1, 2 and 3.
/// A side the file isn't on, such as the one that deleted it, has no version.
/// See https://git-scm.com/docs/git-ls-files#_output
nonisolated struct ConflictStages: Equatable, Sendable {
    struct Version: Equatable, Sendable {
        let mode: String
        let object: String

        var isSymbolicLink: Bool {
            mode == "120000"
        }

        var isSubmodule: Bool {
            mode == "160000"
        }
    }

    var base: Version?
    var ours: Version?
    var theirs: Version?

    static func command(for path: String) -> GitCommand {
        .reading(["ls-files", "--unmerged", "-z", "--", ":(literal)" + path])
    }

    /// Each record is `<mode> <object> <stage>\t<path>`, ended by a NUL.
    init(parsing output: Data) throws {
        for record in output.split(separator: 0) {
            guard let tab = record.firstIndex(of: UInt8(ascii: "\t")),
                  let fields = String(bytes: record[..<tab], encoding: .utf8)?.split(separator: " "),
                  fields.count == 3
            else {
                throw UnreadableGitOutput(reason: "Unknown unmerged entry")
            }
            let version = Version(mode: String(fields[0]), object: String(fields[1]))
            switch fields[2] {
            case "1": base = version
            case "2": ours = version
            case "3": theirs = version
            default: throw UnreadableGitOutput(reason: "Unknown stage")
            }
        }
    }

    init(base: Version? = nil, ours: Version? = nil, theirs: Version? = nil) {
        self.base = base
        self.ours = ours
        self.theirs = theirs
    }

    /// Whether the conflict is in the lines of a file both sides kept, rather than in whether the file
    /// is there at all or in what kind of file it is.
    var isAboutContent: Bool {
        guard let ours, let theirs else { return false }
        let versions = [base, ours, theirs].compactMap(\.self)
        return versions.allSatisfy { !$0.isSymbolicLink && !$0.isSubmodule }
    }
}
