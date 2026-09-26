import Foundation

/// A name the user gives a repository, kept in its `.locus` folder. Shared, the name is left for Git
/// to track, so it travels with the repository. Not shared, the folder holds a `.gitignore` that
/// ignores everything in it but the sidebar's pins, itself included.
nonisolated struct RepositoryDisplayName: Equatable, Sendable {
    /// Nil when the repository has none, and is shown by its folder name.
    let name: String?
    let isShared: Bool

    /// Whether Git already tracks the name. Ignoring it afterwards wouldn't stop that.
    static let trackedFilesCommand = GitCommand.reading(["ls-files", "-z", "--", LocusFolder.path(of: nameFile)])

    private static let nameFile = ".name"

    /// Blocks while macOS asks for permission to read the folder the repository is in.
    static func read(from workTree: URL) -> RepositoryDisplayName {
        let folder = LocusFolder.url(in: workTree)
        let name = (try? String(contentsOf: folder.appending(path: nameFile), encoding: .utf8))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        // With no `.locus` folder yet, nothing is ignored, so a new name starts out shared.
        return RepositoryDisplayName(name: name, isShared: !LocusFolder.hasOwnIgnoreFile(in: folder))
    }

    /// Touches only the files it writes.
    func write(to workTree: URL) throws {
        let folder = LocusFolder.url(in: workTree)
        let manager = FileManager.default
        let trimmed = name.map(Self.oneLine) ?? ""

        if trimmed.isEmpty {
            try? manager.removeItem(at: folder.appending(path: Self.nameFile))
        } else {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data((trimmed + "\n").utf8).write(to: folder.appending(path: Self.nameFile), options: .atomic)
        }

        try LocusFolder.setIgnored(!isShared && !trimmed.isEmpty, in: folder)
        try LocusFolder.removeIfEmpty(folder)
    }

    static func isTracked(_ result: ChildProcess.Result) -> Bool {
        result.status == 0 && !result.standardOutput.isEmpty
    }

    private static func oneLine(_ name: String) -> String {
        name.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
