import AppKit

/// Stages, unstages and discards the working area's files, hunks and lines. Discarding asks first,
/// and keeps the file as it was in the Trash.
final class StagingWorkflow {
    enum Operation {
        case stage
        case unstage
        case discard
    }

    /// Asked for the window to put a confirmation on.
    var window: (() -> NSWindow?)?
    private let commands: RepositoryCommandRunner
    private let options: DiffOptionsStore
    private let queue: WorkingAreaCommandQueue

    init(commands: RepositoryCommandRunner, options: DiffOptionsStore, queue: WorkingAreaCommandQueue) {
        self.commands = commands
        self.options = options
        self.queue = queue
    }

    private var workTree: URL {
        commands.repository.workTree
    }

    /// A conflicted file is staged to mark it resolved.
    func stage(_ files: [DiffFile]) {
        guard ReadOnlyLock.allowsChange(in: window?()) else { return }
        guard !files.isEmpty else { return }
        let paths = files.map(\.changed.path)
        let summary = files.allSatisfy { WorkingAreaGroup($0) == .conflicted }
            ? "Git couldn’t mark \(Self.describe(files)) as resolved."
            : "Git couldn’t stage \(Self.describe(files))."
        queue.run(summary) { [commands] in
            try await WorkingAreaStaging.stage(paths, running: commands.run)
        }
    }

    /// Everything but conflicts, which are for the user to mark resolved one by one.
    func stageAll(excluding conflicts: [DiffFile]) {
        guard ReadOnlyLock.allowsChange(in: window?()) else { return }
        let paths = conflicts.map(\.changed.path)
        queue.run("Git couldn’t stage all the changes.") { [commands] in
            try await WorkingAreaStaging.stageAll(excluding: paths, running: commands.run)
        }
    }

    func stageTracked(excluding conflicts: [DiffFile]) {
        guard ReadOnlyLock.allowsChange(in: window?()) else { return }
        let paths = conflicts.map(\.changed.path)
        queue.run("Git couldn’t stage the unstaged changes.") { [commands] in
            try await WorkingAreaStaging.stageTracked(excluding: paths, running: commands.run)
        }
    }

    func stageUntracked(_ files: [DiffFile]) {
        guard ReadOnlyLock.allowsChange(in: window?()) else { return }
        guard !files.isEmpty else { return }
        let paths = files.map(\.changed.path)
        queue.run("Git couldn’t stage \(Self.describe(files)).") { [commands] in
            try await WorkingAreaStaging.stageUntracked(paths, running: commands.run)
        }
    }

    func unstageAll() {
        guard ReadOnlyLock.allowsChange(in: window?()) else { return }
        queue.run("Git couldn’t unstage the staged changes.") { [commands] in
            try await WorkingAreaStaging.unstageAll(running: commands.run)
        }
    }

    /// Both of a staged rename's paths, so the file isn't left half renamed.
    func unstage(_ files: [DiffFile]) {
        guard ReadOnlyLock.allowsChange(in: window?()) else { return }
        guard !files.isEmpty else { return }
        let paths = files.flatMap { [$0.changed.originalPath, $0.changed.path].compactMap(\.self) }
        queue.run("Git couldn’t unstage \(Self.describe(files)).") { [commands] in
            try await WorkingAreaStaging.unstage(paths, running: commands.run)
        }
    }

    /// An untracked file goes to the Trash. A tracked one goes back to how it's staged, with the
    /// file as it was kept in the Trash. One confirmation covers them all.
    func discard(_ files: [DiffFile]) {
        guard ReadOnlyLock.allowsChange(in: window?()) else { return }
        guard !files.isEmpty, let window = window?() else { return }
        DiscardConfirmation.ask(discardingFiles: files, on: window) { [weak self] in
            self?.discardConfirmed(files[...], keepingCopies: true)
        }
    }

    /// Hunks and lines can't be acted on while whitespace is ignored, since Git's patch then hides
    /// changes that applying it would need, and a file whose only hunk shows would take its hidden
    /// changes along.
    var canActOnHunks: Bool {
        !options.options.ignoresWhitespace
    }

    static let whyHunksCantBeActedOn = "Turn off Ignore Whitespace to stage or discard part of a file."

    /// Whether some of the lines of a file can be unstaged or discarded, rather than all of them: not
    /// back into a deleted file, which isn't there to take them.
    func canPickLines(_ operation: Operation, of file: DiffFile) -> Bool {
        operation == .stage || file.changed.change != .deleted
    }

    /// Why a hunk or lines can't be acted on, for the button's tooltip.
    func whyLinesCantBePicked(_ operation: Operation, of file: DiffFile, isPicking: Bool) -> String? {
        if !canActOnHunks {
            return Self.whyHunksCantBeActedOn
        }
        return isPicking && !canPickLines(operation, of: file) ? "Lines can’t be put back into a deleted file one at a time." : nil
    }

    /// `lines` are indices into the hunk's lines, and all of its changed lines when empty. Picking
    /// every changed line of the file acts on the whole file, which also stages a deletion as one.
    func apply(_ operation: Operation, lines: [Int], hunk: Int, of file: DiffFile) {
        guard ReadOnlyLock.allowsChange(in: window?()) else { return }
        guard canActOnHunks, file.patch.hunks.indices.contains(hunk) else {
            NSSound.beep()
            return
        }
        let changed = Set(file.patch.hunks[hunk].lines.indices.filter { file.patch.hunks[hunk].lines[$0].kind != .context })
        let picked = lines.isEmpty ? changed : changed.intersection(lines)
        guard !picked.isEmpty else { return }
        let isWholeFile = picked == changed && file.patch.hunks.count == 1
        if isWholeFile {
            switch operation {
            case .stage: stage([file])
            case .unstage: unstage([file])
            case .discard: discard([file])
            }
            return
        }
        guard canPickLines(operation, of: file) else {
            NSSound.beep()
            return
        }
        guard operation == .discard else {
            applyPicked(operation, lines: picked, hunk: hunk, of: file)
            return
        }
        guard let window = window?() else { return }
        DiscardConfirmation.ask(discarding: lines.isEmpty ? .hunk : .lines, of: file, on: window) { [weak self] in
            self?.discardPicked(picked, hunk: hunk, of: file, keepingCopy: true)
        }
    }

    /// The Trash takes each file in turn. When it can't take one, the user is asked whether to go on
    /// without it for the files left.
    private func discardConfirmed(_ files: ArraySlice<DiffFile>, keepingCopies: Bool) {
        var tracked: [String] = []
        for (index, file) in zip(files.indices, files) {
            let url = workTree.appending(path: file.changed.path)
            do {
                if WorkingAreaGroup(file) == .untracked {
                    if keepingCopies {
                        try DiscardedVersionTrash.moveToTrash(url)
                    } else {
                        try FileManager.default.removeItem(at: url)
                    }
                } else {
                    if keepingCopies {
                        try DiscardedVersionTrash.keep(url)
                    }
                    tracked.append(file.changed.path)
                }
            } catch {
                restore(tracked, describing: Array(files[..<index]))
                askWithoutTrash(file, because: error) { [weak self] in
                    self?.discardConfirmed(files[index...], keepingCopies: false)
                }
                return
            }
        }
        restore(tracked, describing: Array(files))
    }

    /// Puts tracked files back as they're staged, once the Trash has their copies.
    private func restore(_ paths: [String], describing files: [DiffFile]) {
        guard !paths.isEmpty else {
            queue.noteChange()
            return
        }
        queue.run("Git couldn’t discard the changes to \(Self.describe(files)).") { [commands] in
            try await WorkingAreaStaging.discard(paths, running: commands.run)
        }
    }

    private func discardPicked(_ lines: Set<Int>, hunk: Int, of file: DiffFile, keepingCopy: Bool) {
        if keepingCopy {
            do {
                try DiscardedVersionTrash.keep(workTree.appending(path: file.changed.path))
            } catch {
                askWithoutTrash(file, because: error) { [weak self] in
                    self?.discardPicked(lines, hunk: hunk, of: file, keepingCopy: false)
                }
                return
            }
        }
        applyPicked(.discard, lines: lines, hunk: hunk, of: file)
    }

    /// Read again as Git writes it, and only applied when it's still what the diff showed.
    private func applyPicked(_ operation: Operation, lines: Set<Int>, hunk: Int, of file: DiffFile) {
        let options = options.options
        let summary = switch operation {
        case .stage: "Git couldn’t stage the lines picked in \(Self.describe([file]))."
        case .unstage: "Git couldn’t unstage the lines picked in \(Self.describe([file]))."
        case .discard: "Git couldn’t discard the lines picked in \(Self.describe([file]))."
        }
        queue.run(summary) { [commands, workTree] in
            let raw = try await WorkingAreaDiff.readRawPatch(of: file, options: options, workTree: workTree, running: commands.run)
            guard let raw, raw.matches(file.patch) else {
                throw WorkingAreaCommandQueue.ChangedSinceShown()
            }
            let direction: PartialPatch.Direction = operation == .stage ? .forward : .reverse
            guard let patch = PartialPatch.make(from: raw, hunk: hunk, lines: lines, path: file.changed.path, direction: direction) else {
                return
            }
            try await WorkingAreaStaging.apply(
                patch,
                toIndex: operation != .discard,
                reverse: operation != .stage,
                contextLines: options.contextLines,
                running: commands.run
            )
        }
    }

    private func askWithoutTrash(_ file: DiffFile, because error: any Error, then discard: @escaping () -> Void) {
        guard let window = window?() else { return }
        DiscardConfirmation.askWithoutTrash(for: file, because: error, on: window, then: discard)
    }

    /// “name.swift”, or how many files.
    private static func describe(_ files: [DiffFile]) -> String {
        guard files.count == 1, let file = files.first else { return "\(files.count.formatted()) files" }
        return "“\((file.changed.path as NSString).lastPathComponent)”"
    }
}
