import AppKit

/// The menu a ⌘-click on the title shows: the repository's folder and each folder it's in. Choosing
/// one shows it in Finder with the folder below it selected, as AppKit's own title does.
final class RepositoryPathMenu: NSObject {
    private let folders: [URL]

    init(folder: URL) {
        var folders = [folder.standardizedFileURL]
        while let last = folders.last, last.path != "/" {
            folders.append(last.deletingLastPathComponent())
        }
        self.folders = folders
    }

    /// Opens with the repository's folder under the pointer, as AppKit's own title does.
    func popUp(at point: NSPoint, in view: NSView) {
        let menu = makeMenu()
        menu.popUp(positioning: menu.items.first, at: point, in: view)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        for (index, folder) in folders.enumerated() {
            let item = NSMenuItem(
                title: FileManager.default.displayName(atPath: folder.path),
                action: #selector(choose(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.image = NSWorkspace.shared.icon(forFile: folder.path)
            item.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(item)
        }
        return menu
    }

    @objc private func choose(_ sender: NSMenuItem) {
        let selecting = sender.tag == 0 ? folders[0] : folders[sender.tag - 1]
        NSWorkspace.shared.activateFileViewerSelecting([selecting])
    }
}
