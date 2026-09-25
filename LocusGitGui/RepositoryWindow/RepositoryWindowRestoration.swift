import AppKit

/// Brings repository windows back after a relaunch, following "Close windows when quitting an
/// application" in System Settings. macOS keeps each window's frame, screen and tab group; the
/// window itself only records which repository it shows.
final class RepositoryWindowRestoration: NSObject, NSWindowRestoration {
    static let identifier = NSUserInterfaceItemIdentifier("RepositoryWindow")

    private static let workTreeKey = "workTree"
    private static let gitDirectoryKey = "gitDirectory"

    static func encode(_ repository: Repository, into state: NSCoder) {
        state.encode(repository.workTree.path as NSString, forKey: workTreeKey)
        state.encode(repository.gitDirectory.path as NSString, forKey: gitDirectoryKey)
    }

    static func restoreWindow(
        withIdentifier _: NSUserInterfaceItemIdentifier,
        state: NSCoder,
        completionHandler: @escaping (NSWindow?, (any Error)?) -> Void
    ) {
        guard let workTree = state.decodeObject(of: NSString.self, forKey: workTreeKey),
              let gitDirectory = state.decodeObject(of: NSString.self, forKey: gitDirectoryKey),
              let appDelegate = NSApp.delegate as? AppDelegate
        else {
            completionHandler(nil, CocoaError(.coderReadCorrupt))
            return
        }
        appDelegate.restoreWindow(
            for: Repository(
                workTree: URL(filePath: workTree as String, directoryHint: .isDirectory),
                gitDirectory: URL(filePath: gitDirectory as String, directoryHint: .isDirectory)
            ),
            completionHandler: completionHandler
        )
    }
}
