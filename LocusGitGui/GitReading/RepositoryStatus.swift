import Foundation

/// The checked-out branch and every changed file, from `git status --porcelain=v2`.
/// See https://git-scm.com/docs/git-status#_porcelain_format_version_2
nonisolated struct RepositoryStatus: Equatable, Sendable {
    struct Branch: Equatable, Sendable {
        /// Nil before the first commit.
        let commit: String?
        /// Nil when HEAD is detached.
        let name: String?
        let upstream: String?
        let ahead: Int?
        let behind: Int?
    }

    struct File: Equatable, Sendable {
        let path: String
        /// Where a renamed or copied file came from.
        let originalPath: String?
        let state: FileState
    }

    enum FileState: Equatable, Sendable {
        case changed(staged: Change?, unstaged: Change?)
        case conflicted(Conflict)
        case untracked
        case ignored
    }

    enum Change: Character, Sendable {
        case modified = "M"
        case typeChanged = "T"
        case added = "A"
        case deleted = "D"
        case renamed = "R"
        case copied = "C"
    }

    enum Conflict: String, Sendable {
        case bothDeleted = "DD"
        case addedByUs = "AU"
        case deletedByThem = "UD"
        case addedByThem = "UA"
        case deletedByUs = "DU"
        case bothAdded = "AA"
        case bothModified = "UU"
    }

    static let command = GitCommand.reading(["status", "--porcelain=v2", "--branch", "-z"])

    let branch: Branch
    let files: [File]

    init(branch: Branch, files: [File]) {
        self.branch = branch
        self.files = files
    }

    /// Split as bytes rather than as text, where a path starting with a combining mark would join
    /// the space in front of it into one character.
    init(parsing output: Data) throws {
        var headers: [String: String] = [:]
        var files: [File] = []
        var records = output.split(separator: 0).makeIterator()

        while let record = records.next() {
            switch record.first {
            case UInt8(ascii: "#"):
                let header = try Self.fields(of: record.dropFirst(2), count: 2)
                headers[header[0]] = header[1]
            case UInt8(ascii: "1"):
                files.append(try Self.ordinaryFile(record))
            case UInt8(ascii: "2"):
                // The original path is the next NUL-separated record.
                guard let originalPath = records.next() else {
                    throw UnreadableGitOutput(reason: "Rename without an original path")
                }
                files.append(try Self.renamedFile(record, from: UnreadableGitOutput.text(originalPath)))
            case UInt8(ascii: "u"):
                files.append(try Self.conflictedFile(record))
            case UInt8(ascii: "?"):
                files.append(File(path: try UnreadableGitOutput.text(record.dropFirst(2)), originalPath: nil, state: .untracked))
            case UInt8(ascii: "!"):
                files.append(File(path: try UnreadableGitOutput.text(record.dropFirst(2)), originalPath: nil, state: .ignored))
            default:
                throw UnreadableGitOutput(reason: "Unknown status record")
            }
        }

        branch = Self.branch(from: headers)
        self.files = files
    }

    private static func branch(from headers: [String: String]) -> Branch {
        let commit = headers["branch.oid"].flatMap { $0 == "(initial)" ? nil : $0 }
        let name = headers["branch.head"].flatMap { $0 == "(detached)" ? nil : $0 }
        let counts = headers["branch.ab"]?.split(separator: " ")
        return Branch(
            commit: commit,
            name: name,
            upstream: headers["branch.upstream"],
            ahead: counts?.first.flatMap { Int($0.dropFirst()) },
            behind: counts?.last.flatMap { Int($0.dropFirst()) }
        )
    }

    /// `1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>`
    private static func ordinaryFile(_ record: Data) throws -> File {
        let fields = try fields(of: record, count: 9)
        return File(path: fields[8], originalPath: nil, state: try changedState(fields[1]))
    }

    /// `2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>`
    private static func renamedFile(_ record: Data, from originalPath: String) throws -> File {
        let fields = try fields(of: record, count: 10)
        return File(path: fields[9], originalPath: originalPath, state: try changedState(fields[1]))
    }

    /// `u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>`
    private static func conflictedFile(_ record: Data) throws -> File {
        let fields = try fields(of: record, count: 11)
        guard let conflict = Conflict(rawValue: fields[1]) else {
            throw UnreadableGitOutput(reason: "Unknown conflict")
        }
        return File(path: fields[10], originalPath: nil, state: .conflicted(conflict))
    }

    /// The path comes last and can itself contain spaces, so splitting stops before it.
    private static func fields(of record: Data, count: Int) throws -> [String] {
        let fields = record.split(separator: UInt8(ascii: " "), maxSplits: count - 1, omittingEmptySubsequences: false)
        guard fields.count == count else {
            throw UnreadableGitOutput(reason: "Status record has \(fields.count) fields, expected \(count)")
        }
        return try fields.map(UnreadableGitOutput.text)
    }

    /// `.` means unchanged on that side.
    private static func changedState(_ codes: String) throws -> FileState {
        guard codes.count == 2, let staged = codes.first, let unstaged = codes.last else {
            throw UnreadableGitOutput(reason: "Malformed change codes")
        }
        return try .changed(staged: change(staged), unstaged: change(unstaged))
    }

    private static func change(_ code: Character) throws -> Change? {
        if code == "." {
            return nil
        }
        guard let change = Change(rawValue: code) else {
            throw UnreadableGitOutput(reason: "Unknown change code")
        }
        return change
    }
}
