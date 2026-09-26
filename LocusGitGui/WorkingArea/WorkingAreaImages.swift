import Foundation

/// One side of an image in the working area: from Git's objects for what's committed and staged, and
/// from the file itself for what isn't staged yet.
enum WorkingAreaImages {
    static func read(
        _ file: DiffFile,
        isNew: Bool,
        workTree: URL,
        running run: (GitCommand) async throws -> ChildProcess.Result
    ) async throws -> (data: Data?, byteCount: Int)? {
        switch (WorkingAreaGroup(file), isNew) {
        case (.staged, _), (.unstaged, false):
            return try await CommitDetailViewController.readImage(isNew ? file.changed.newObject : file.changed.oldObject, running: run)
        case (.unstaged, true), (.untracked, true):
            return try await readFromDisk(file.changed.path, in: workTree)
        default:
            return nil
        }
    }

    /// Nil when the file isn't there, such as one deleted and not yet staged.
    @concurrent
    private static func readFromDisk(_ path: String, in workTree: URL) async throws -> (data: Data?, byteCount: Int)? {
        let url = workTree.appending(path: path)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        guard size <= DiffImage.byteLimit else { return (nil, size) }
        return (try Data(contentsOf: url), size)
    }
}
