import AppKit

/// A changed file as it is in the working tree now, which is what Open in Editor and Reveal in
/// Finder act on. A file a commit deleted, or one renamed since, isn't there, and those are
/// disabled; the Copy Path commands still give where it would be.
struct WorkingTreeFile {
    let url: URL
    /// From the top of the working tree, as Git names it.
    let path: String

    init(path: String, in workTree: URL) {
        self.path = path
        url = workTree.appending(path: path, directoryHint: .notDirectory)
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func copyAbsolutePath() {
        putOnPasteboard(url.path)
    }

    func copyPathFromRepositoryRoot() {
        putOnPasteboard(path)
    }

    private func putOnPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// In the app macOS opens the file with, which is the user's choice for that kind of file.
    func openInEditor() {
        NSWorkspace.shared.open(url)
    }
}
