import AppKit

/// The Files & Folders list in Privacy & Security, where the user allows the app into a folder
/// macOS has kept it out of.
enum PrivacySettings {
    private static let filesAndFoldersURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")

    static func openFilesAndFolders() {
        if let filesAndFoldersURL {
            NSWorkspace.shared.open(filesAndFoldersURL)
        }
    }
}
