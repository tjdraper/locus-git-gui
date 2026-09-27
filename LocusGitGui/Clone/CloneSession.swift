import Foundation

/// What the Clone Repository window is set to: the address, the folder it goes in, the new folder's
/// name, and whether submodules come too. The name follows the address until the user changes it.
@Observable
final class CloneSession {
    private static let parentFolderKey = "CloneParentFolder"

    var address = "" {
        didSet {
            guard !isFolderNameEdited else { return }
            folderName = RemoteURL.repositoryName(from: address) ?? ""
        }
    }

    var parentFolder: URL
    private(set) var folderName = ""
    var includesSubmodules = true
    /// Set once the user types a name of their own, which a later address doesn't replace.
    private var isFolderNameEdited = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        parentFolder = Self.rememberedParentFolder(in: defaults)
    }

    func setFolderName(_ name: String) {
        folderName = name
        isFolderNameEdited = !name.isEmpty
    }

    var destination: URL {
        parentFolder.appending(path: folderName, directoryHint: .isDirectory)
    }

    var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Why the clone can't start, checked before anything runs. Nil while there's nothing to check.
    var problem: String? {
        if folderName.contains("/") || folderName == "." || folderName == ".." {
            return "The folder’s name can’t contain a slash."
        }
        guard !folderName.isEmpty else { return nil }
        let contents = try? FileManager.default.contentsOfDirectory(atPath: destination.path)
        if let contents, !contents.isEmpty {
            return "“\(folderName)” already exists in “\(parentFolder.lastPathComponent)” and isn’t empty."
        }
        if contents == nil, FileManager.default.fileExists(atPath: destination.path) {
            return "There’s already a file named “\(folderName)” in “\(parentFolder.lastPathComponent)”."
        }
        return nil
    }

    var canClone: Bool {
        !trimmedAddress.isEmpty && !folderName.isEmpty && problem == nil
    }

    /// Kept for the next clone, since repositories tend to go in the same place.
    func rememberParentFolder() {
        defaults.set(parentFolder.path, forKey: Self.parentFolderKey)
    }

    /// The last clone’s, or `~/Developer` when it exists, which many people keep repositories in.
    private static func rememberedParentFolder(in defaults: UserDefaults) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let path = defaults.string(forKey: parentFolderKey) {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        let developer = home.appending(path: "Developer", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: developer.path) ? developer : home
    }
}
