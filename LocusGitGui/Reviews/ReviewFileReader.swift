import Foundation

/// Reads the review window's file: its changes for the review, or only those since it was last
/// reviewed, and its images.
struct ReviewFileReader {
    let session: ReviewSession
    let options: DiffOptionsStore

    func read(_ entry: ReviewSession.Entry, sinceReviewed: Bool, limits: PatchParser.Limits) async throws -> DiffFile {
        guard let revision = session.review?.revision else { throw CancellationError() }
        let commands = session.commands
        if sinceReviewed, let reviewed = session.review?.checks.reviewedVersion(of: entry.file.path)?.newObject,
           var current = entry.file.newObject {
            if revision.includesWorkingTree {
                current = try await session.storeWorkingTreeFile(entry.file.path)
            }
            return try await ReviewDiff.readChangesSince(
                (reviewed, current),
                in: entry.file,
                options: options.options,
                limits: limits,
                readingPatch: commands.readPatch
            )
        }
        return try await ReviewDiff.readFile(
            entry.file,
            isUntracked: entry.isUntracked,
            from: ReviewDiff.Source(revision: revision, options: options.options, workTree: session.repository.workTree),
            limits: limits,
            readingPatch: commands.readPatch
        )
    }

    /// The new side of a file in the working tree is read from disk, as the working area reads it.
    func readImage(_ file: DiffFile, isNew: Bool) async throws -> (data: Data?, byteCount: Int)? {
        let commands = session.commands
        if isNew, session.review?.revision?.includesWorkingTree == true {
            let url = session.repository.workTree.appending(path: file.changed.path)
            let data = try? Data(contentsOf: url)
            return (data, data?.count ?? 0)
        }
        let object = isNew ? file.changed.newObject : file.changed.oldObject
        return try await CommitDetailViewController.readImage(object, running: commands.run)
    }
}
