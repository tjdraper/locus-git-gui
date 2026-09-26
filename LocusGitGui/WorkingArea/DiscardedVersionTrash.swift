import Foundation

/// Keeps a copy of a file in the Trash before its changes are discarded. The file itself goes to the
/// Trash, so Put Back knows where it came from, and a copy takes its place until Git changes it.
enum DiscardedVersionTrash {
    /// Nothing is kept for a file that isn't there, such as one deleted and not yet staged.
    static func keep(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) || isSymbolicLink(url) else { return }
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        guard let trashed = trashed as URL? else { return }
        try FileManager.default.copyItem(at: trashed, to: url)
    }

    /// For an untracked file, whose only copy the Trash then holds.
    static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
