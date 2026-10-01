import Foundation

/// A file in a review as Git sees it: where it is, and the mode and contents on each side. Two are
/// the same file in the same state when every field matches, which is how a check knows whether
/// the file has changed since.
nonisolated struct ReviewedFile: Codable, Hashable, Sendable {
    let path: String
    let originalPath: String?
    let oldMode: String
    let newMode: String
    /// Nil on the side the file isn't on.
    let oldObject: String?
    let newObject: String?

    init(path: String, originalPath: String? = nil, oldMode: String, newMode: String, oldObject: String?, newObject: String?) {
        self.path = path
        self.originalPath = originalPath
        self.oldMode = oldMode
        self.newMode = newMode
        self.oldObject = oldObject
        self.newObject = newObject
    }

    init(_ file: ChangedFile) {
        self.init(
            path: file.path,
            originalPath: file.originalPath,
            oldMode: file.oldMode,
            newMode: file.newMode,
            oldObject: file.oldObject,
            newObject: file.newObject
        )
    }

    /// A submodule's objects are commits in another repository, which this one can't keep.
    var keptObjects: [String] {
        [(oldMode, oldObject), (newMode, newObject)].compactMap { mode, object in
            mode == ChangedFile.submoduleMode ? nil : object
        }
    }
}
