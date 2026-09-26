import Foundation

/// A file a diff changed, from `--raw -z --no-abbrev`: what happened to it, where it is, and the
/// modes and objects on each side.
nonisolated struct ChangedFile: Equatable, Sendable {
    enum Change: Sendable {
        case added
        case copied
        case deleted
        case modified
        case renamed
        case typeChanged
        case unmerged
        case unknown

        /// Git's status letters. A rename or copy is followed by how similar the two files are,
        /// such as `R086`.
        init(letter: Character?) {
            switch letter {
            case "A": self = .added
            case "C": self = .copied
            case "D": self = .deleted
            case "M": self = .modified
            case "R": self = .renamed
            case "T": self = .typeChanged
            case "U": self = .unmerged
            default: self = .unknown
            }
        }

        var title: String {
            switch self {
            case .added: "Added"
            case .copied: "Copied"
            case .deleted: "Deleted"
            case .modified: "Modified"
            case .renamed: "Renamed"
            case .typeChanged: "Type Changed"
            case .unmerged: "Unmerged"
            case .unknown: "Changed"
            }
        }

        /// A rename or copy names the file it came from as well.
        var hasOriginalPath: Bool {
            self == .renamed || self == .copied
        }
    }

    /// Git's modes for a file that isn't there, a symbolic link, and a submodule.
    static let absentMode = "000000"
    static let linkMode = "120000"
    static let submoduleMode = "160000"
    private static let executableMode = "100755"
    private static let imageExtensions: Set<String> = [
        "bmp", "gif", "heic", "heif", "icns", "ico", "jpeg", "jpg", "png", "tif", "tiff", "webp",
    ]

    let change: Change
    let path: String
    let originalPath: String?
    var oldMode = absentMode
    var newMode = absentMode
    /// Nil on the side the file isn't on. Git writes a hash of zeros there, and for a file in the
    /// working tree that it hasn't hashed.
    var oldObject: String?
    var newObject: String?

    var isImage: Bool {
        let modes = [oldMode, newMode]
        guard !modes.contains(Self.linkMode), !modes.contains(Self.submoduleMode) else { return false }
        return Self.imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Worded for people, such as "Made executable". Nil when the mode didn't change, or the file
    /// was added, deleted or changed type, whose modes say nothing more than that.
    var modeChange: String? {
        guard oldMode != newMode, oldMode != Self.absentMode, newMode != Self.absentMode, change != .typeChanged else {
            return nil
        }
        if newMode == Self.executableMode {
            return "Made executable"
        }
        if oldMode == Self.executableMode {
            return "No longer executable"
        }
        return "Mode changed from \(oldMode) to \(newMode)"
    }

    /// Each entry is `:<old mode> <new mode> <old object> <new object> <status>`, then the path, or
    /// for a rename or copy the path it came from and then the path it went to, each ending in NUL.
    static func parseRaw(_ output: Data) throws -> [ChangedFile] {
        var fields = output.split(separator: 0, omittingEmptySubsequences: false).makeIterator()
        var files: [ChangedFile] = []
        while let entry = fields.next(), !entry.isEmpty {
            let parts = try UnreadableGitOutput.text(entry).split(separator: " ")
            guard parts.count == 5, parts[0].hasPrefix(":") else {
                throw UnreadableGitOutput(reason: "Changed file entry isn’t in raw format")
            }
            let change = Change(letter: parts[4].first)
            guard let first = fields.next(), !first.isEmpty else {
                throw UnreadableGitOutput(reason: "Changed file without a path")
            }
            var path = try UnreadableGitOutput.text(first)
            var originalPath: String?
            if change.hasOriginalPath {
                guard let second = fields.next(), !second.isEmpty else {
                    throw UnreadableGitOutput(reason: "Rename without a new path")
                }
                originalPath = path
                path = try UnreadableGitOutput.text(second)
            }
            files.append(ChangedFile(
                change: change,
                path: path,
                originalPath: originalPath,
                oldMode: String(parts[0].dropFirst()),
                newMode: String(parts[1]),
                oldObject: object(parts[2]),
                newObject: object(parts[3])
            ))
        }
        return files
    }

    private static func object(_ hash: Substring) -> String? {
        hash.allSatisfy { $0 == "0" } ? nil : String(hash)
    }
}
