import Foundation

/// A name the user gives a repository, kept in a `.locus` folder at the top of its working tree.
/// Shared, the folder is left for Git to track, so the name travels with the repository. Not
/// shared, the folder holds a `.gitignore` that ignores everything in it, itself included.
nonisolated struct RepositoryDisplayName: Equatable, Sendable {
    /// Nil when the repository has none, and is shown by its folder name.
    let name: String?
    let isShared: Bool

    /// Anything in `.locus` Git already tracks. Ignoring the folder afterwards wouldn't stop that.
    static let trackedFilesCommand = GitCommand.reading(["ls-files", "-z", "--", folderName])

    private static let folderName = ".locus"
    private static let nameFile = ".name"
    private static let ignoreFile = ".gitignore"
    private static let ignoreEverything = "*\n"

    /// Blocks while macOS asks for permission to read the folder the repository is in.
    static func read(from workTree: URL) -> RepositoryDisplayName {
        let folder = folder(in: workTree)
        let name = (try? String(contentsOf: folder.appending(path: nameFile), encoding: .utf8))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        // With no `.locus` folder yet, nothing is ignored, so a new name starts out shared.
        return RepositoryDisplayName(name: name, isShared: !hasOwnIgnoreFile(in: folder))
    }

    /// Touches only the files it writes. Anything else someone put in `.locus` stays, and so does
    /// the folder while it holds anything.
    func write(to workTree: URL) throws {
        let folder = Self.folder(in: workTree)
        let manager = FileManager.default
        let trimmed = name.map(Self.oneLine) ?? ""

        if trimmed.isEmpty {
            try? manager.removeItem(at: folder.appending(path: Self.nameFile))
        } else {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data((trimmed + "\n").utf8).write(to: folder.appending(path: Self.nameFile), options: .atomic)
        }

        if isShared || trimmed.isEmpty {
            if Self.hasOwnIgnoreFile(in: folder) {
                try manager.removeItem(at: folder.appending(path: Self.ignoreFile))
            }
        } else {
            try Data(Self.ignoreEverything.utf8).write(to: folder.appending(path: Self.ignoreFile), options: .atomic)
        }

        if (try? manager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try manager.removeItem(at: folder)
        }
    }

    static func isTracked(_ result: ChildProcess.Result) -> Bool {
        result.status == 0 && !result.standardOutput.isEmpty
    }

    private static func folder(in workTree: URL) -> URL {
        workTree.appending(path: folderName, directoryHint: .isDirectory)
    }

    /// Only the file this writes counts, so a `.gitignore` someone wrote by hand is left alone.
    private static func hasOwnIgnoreFile(in folder: URL) -> Bool {
        (try? String(contentsOf: folder.appending(path: ignoreFile), encoding: .utf8)) == ignoreEverything
    }

    private static func oneLine(_ name: String) -> String {
        name.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
