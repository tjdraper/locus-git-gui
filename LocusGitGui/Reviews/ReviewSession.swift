import Foundation
import os

/// One open review: its files as of the last read, which one is picked, and checking them off.
@Observable
final class ReviewSession {
    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "Reviews")

    struct Entry: Identifiable, Equatable {
        let file: ChangedFile
        let state: ReviewChecks.State
        let isUntracked: Bool
        let unresolvedThreads: Int

        var id: String {
            file.path
        }

        var reviewed: ReviewedFile {
            ReviewedFile(file)
        }
    }

    /// The list's first row, which shows the review's comments in place of a file.
    static let overviewTag = "\u{1}comments"

    let id: UUID
    let repository: Repository
    @ObservationIgnored let store: ReviewStore
    @ObservationIgnored let commands: RepositoryCommandRunner
    /// Nil until the files have been read once.
    private(set) var listing: ReviewDiff.Listing?
    private(set) var readFailure: GitReadFailure?
    /// The repository's branches and tags as of the last refresh, for choosing the points.
    private(set) var refs: [Ref] = []
    /// For a point fixed at a commit, the branches that contain it, which it can be moved along to.
    private(set) var containing: [String: [Ref]] = [:]
    @ObservationIgnored private var head: String?
    var hidesChecked = false {
        didSet {
            if hidesChecked != oldValue {
                onPlaceChange?()
            }
        }
    }

    /// The path of the file shown.
    var selection: String? {
        didSet {
            if selection != oldValue {
                onSelectionChange?(selection)
                onPlaceChange?()
            }
        }
    }

    /// Files changed since they were reviewed show only those changes, apart from these.
    var showsWholeDiff: Set<String> = []
    @ObservationIgnored var onSelectionChange: ((String?) -> Void)?
    @ObservationIgnored var onPlaceChange: (() -> Void)?
    /// Whenever the listing or a file's state changes, for the diff to follow.
    @ObservationIgnored var onFilesChange: (() -> Void)?
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    /// What the repository has been asked to keep for this review, so it's only asked again when
    /// there's more.
    @ObservationIgnored private var kept: Set<String> = []

    init(id: UUID, store: ReviewStore, commands: RepositoryCommandRunner) {
        self.id = id
        self.store = store
        self.commands = commands
        repository = commands.repository
    }

    var review: Review? {
        store.review(id, in: repository)
    }

    /// The files the list shows. A file checked while checked files are hidden stays until another
    /// is picked, so it doesn't vanish from under the pointer.
    var entries: [Entry] {
        guard let listing, let review else { return [] }
        let threads = Dictionary(grouping: review.threads.filter { !$0.isResolved }) { $0.place.path ?? "" }
        return listing.files.compactMap { file in
            let state = review.checks.state(of: ReviewedFile(file))
            if hidesChecked, state == .checked, file.path != selection {
                return nil
            }
            return Entry(
                file: file,
                state: state,
                isUntracked: listing.untracked.contains(file.path),
                unresolvedThreads: threads[file.path]?.count ?? 0
            )
        }
    }

    var selectedEntry: Entry? {
        entries.first { $0.file.path == selection }
    }

    /// After every refresh of the repository.
    func refresh(refs: [Ref], head: String?) {
        self.refs = refs
        self.head = head
        refreshing?.cancel()
        refreshing = Task { [weak self] in
            guard let self else { return }
            do {
                guard let (_, listing) = try await ReviewRefresh.run(id, store: store, refs: refs, head: head, commands: commands),
                      !Task.isCancelled
                else { return }
                readFailure = nil
                if listing != self.listing {
                    self.listing = listing
                }
                await readContainingBranches(refs: refs)
                if selection == nil || selection != Self.overviewTag && !listing.files.contains(where: { $0.path == selection }) {
                    selection = entries.first { $0.state != .checked }?.file.path ?? entries.first?.file.path
                }
                onFilesChange?()
            } catch is CancellationError {
                return
            } catch is RepositoryCommandRunner.NoUsableGit {
                return
            } catch let failure as GitReadFailure {
                readFailure = failure
            } catch {
                Self.log.error("Reading a review failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    private func readContainingBranches(refs: [Ref]) async {
        var containing: [String: [Ref]] = [:]
        for point in [review?.base, review?.head] {
            guard case let .commit(hash) = point else { continue }
            let command = GitCommand.reading(["for-each-ref", "--format=%(refname)", "--contains", hash, "refs/heads", "refs/remotes"])
            guard let names = try? await GitReadFailure.read("branches", with: command, running: commands.run, parse: { output in
                try UnreadableGitOutput.text(output).split(separator: "\n").map(String.init)
            }) else { continue }
            containing[hash] = refs.filter { names.contains($0.name) && $0.symbolicTarget == nil && $0.commit != hash }
        }
        if containing != self.containing {
            self.containing = containing
        }
    }

    func isChecked(_ path: String) -> Bool {
        entries.first { $0.file.path == path }?.state == .checked
    }

    /// Checks the file off, or unchecks it.
    func toggleCheck(_ path: String) {
        guard let entry = listing?.files.first(where: { $0.path == path }), let review else { return }
        if review.checks.state(of: ReviewedFile(entry)) == .checked {
            store.update(id, in: repository) { review in
                review.checks.uncheck(path)
                review.lastChanged = Date()
                review.progress = progress(of: review)
            }
            onFilesChange?()
            return
        }
        Task { await check(entry) }
    }

    /// A file in the working tree has its contents stored first, so the check can be compared with
    /// the file as it is later.
    private func check(_ file: ChangedFile) async {
        var reviewed = ReviewedFile(file)
        if review?.revision?.includesWorkingTree == true, listing?.files.contains(file) == true,
           file.newMode != ChangedFile.absentMode, file.newMode != ChangedFile.submoduleMode {
            do {
                let stored = try await storeWorkingTreeFile(file.path)
                reviewed = ReviewedFile(
                    path: file.path,
                    originalPath: file.originalPath,
                    oldMode: file.oldMode,
                    newMode: file.newMode,
                    oldObject: file.oldObject,
                    newObject: stored
                )
            } catch {
                Self.log.error("Storing a reviewed file failed: \(String(describing: type(of: error)), privacy: .public)")
                return
            }
        }
        store.update(id, in: repository) { review in
            review.checks.check(reviewed, at: Date())
            review.lastChanged = Date()
            review.progress = progress(of: review)
        }
        onFilesChange?()
        await keepObjects()
    }

    func storeWorkingTreeFile(_ path: String) async throws -> String {
        try await GitReadFailure.read("file", with: ReviewDiff.storeCommand(path), running: commands.run) { output in
            try UnreadableGitOutput.text(output).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func progress(of review: Review) -> Review.Progress {
        ReviewFollowing.progress(of: listing?.files.map(ReviewedFile.init) ?? [], in: review.checks)
    }

    /// Points the review's hidden ref at everything its checks and comments refer to.
    func keepObjects() async {
        guard let objects = review?.keptObjects, !objects.isSubset(of: kept) else { return }
        do {
            let tree = try await GitReadFailure.read("kept files", with: ReviewKeptObjects.treeCommand(objects), running: commands.run) {
                try UnreadableGitOutput.text($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let result = try await commands.run(ReviewKeptObjects.pointCommand(for: id, at: tree))
            if result.status == 0 {
                kept = objects
            }
        } catch {
            Self.log.error("Keeping a review's files failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// The next file not yet checked off after the one shown, going round to the start.
    var nextUncheckedPath: String? {
        let files = entries
        let start = files.firstIndex { $0.file.path == selection } ?? -1
        let after = files[(start + 1)...] + files[..<max(start, 0)]
        return after.first { $0.state != .checked }?.file.path
    }

    /// Checks off the file shown and moves on to the next one not yet checked.
    func checkAndMoveOn() {
        guard let selection, selectedEntry != nil else { return }
        let wasChecked = isChecked(selection)
        let next = nextUncheckedPath
        toggleCheck(selection)
        if !wasChecked, let next {
            self.selection = next
        }
    }

    func move(by offset: Int) -> Bool {
        let files = entries
        guard let index = files.firstIndex(where: { $0.file.path == selection }), files.indices.contains(index + offset) else {
            return false
        }
        selection = files[index + offset].file.path
        return true
    }

    func canMove(by offset: Int) -> Bool {
        let files = entries
        guard let index = files.firstIndex(where: { $0.file.path == selection }) else { return false }
        return files.indices.contains(index + offset)
    }

    /// Both points at once, which records a revision at the next refresh.
    func setPoints(base: ReviewPoint, head: ReviewPoint) {
        store.update(id, in: repository) { review in
            review.base = base
            review.head = head
            review.lastChanged = Date()
        }
        refresh(refs: refs, head: self.head)
    }

    func stop() {
        refreshing?.cancel()
    }
}
