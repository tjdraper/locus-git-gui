import Foundation

/// The `.locus` folder at the top of a repository's working tree, which holds what the app keeps
/// about a repository that belongs with the repository rather than with one Mac: its display name
/// and the sidebar's pins. Git sees the folder like any other, so it's shared once committed.
nonisolated enum LocusFolder {
    static let pinsFile = ".pinned"

    private static let name = ".locus"
    private static let ignoreFile = ".gitignore"
    /// Written while the display name isn't shared. It ignores everything in the folder, itself
    /// included, apart from the pins, which are always shared.
    private static let ignoreAllButPins = "*\n!/\(pinsFile)\n"
    /// Written before there were pins, and ignores them as well.
    private static let ignoreEverything = "*\n"

    static func url(in workTree: URL) -> URL {
        workTree.appending(path: name, directoryHint: .isDirectory)
    }

    /// A file's path from the top of the working tree, as Git names it.
    static func path(of file: String) -> String {
        "\(name)/\(file)"
    }

    /// Only the file the app writes counts, so a `.gitignore` someone wrote by hand is left alone.
    static func hasOwnIgnoreFile(in folder: URL) -> Bool {
        let contents = try? String(contentsOf: folder.appending(path: ignoreFile), encoding: .utf8)
        return contents == ignoreAllButPins || contents == ignoreEverything
    }

    /// Ignores everything in the folder but the pins, or stops ignoring it.
    static func setIgnored(_ isIgnored: Bool, in folder: URL) throws {
        let file = folder.appending(path: ignoreFile)
        if isIgnored {
            try Data(ignoreAllButPins.utf8).write(to: file, options: .atomic)
        } else if hasOwnIgnoreFile(in: folder) {
            try FileManager.default.removeItem(at: file)
        }
    }

    /// An ignore file written before there were pins would keep them from being shared.
    static func letPinsBeShared(in folder: URL) throws {
        if hasOwnIgnoreFile(in: folder) {
            try setIgnored(true, in: folder)
        }
    }

    /// Anything someone else put in the folder stays, and so does the folder while it holds anything.
    static func removeIfEmpty(_ folder: URL) throws {
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try FileManager.default.removeItem(at: folder)
        }
    }
}
