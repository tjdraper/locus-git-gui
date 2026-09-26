import Foundation

/// What's pinned to the top of the sidebar, in the order it was pinned. Kept in the repository's
/// `.locus` folder and always left for Git to track, so once committed everyone who clones the
/// repository has the same pins. A line for each: a branch, remote branch or tag by its full ref
/// name, or `stash` and the stash's commit, which stays the same as other stashes come and go.
nonisolated struct SidebarPins: Equatable, Sendable {
    private static let stashPrefix = "stash "

    private(set) var items: [SidebarItemID]

    init(_ items: [SidebarItemID] = []) {
        self.items = items
    }

    /// A remote holds branches rather than being one, so it isn't pinned.
    static func canPin(_ id: SidebarItemID) -> Bool {
        switch id {
        case .ref, .stash: true
        case .remote: false
        }
    }

    func contains(_ id: SidebarItemID) -> Bool {
        items.contains(id)
    }

    /// Pinned last, or unpinned.
    mutating func toggle(_ id: SidebarItemID) {
        guard Self.canPin(id) else { return }
        if let index = items.firstIndex(of: id) {
            items.remove(at: index)
        } else {
            items.append(id)
        }
    }

    /// Blocks while macOS asks for permission to read the folder the repository is in. Lines it
    /// doesn't recognize are skipped.
    static func read(from workTree: URL) -> SidebarPins {
        let file = LocusFolder.url(in: workTree).appending(path: LocusFolder.pinsFile)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return SidebarPins() }
        return SidebarPins(parsing: text)
    }

    init(parsing text: String) {
        var items: [SidebarItemID] = []
        for line in text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let id: SidebarItemID? = if line.hasPrefix("refs/") {
                .ref(line)
            } else if line.hasPrefix(Self.stashPrefix) {
                .stash(String(line.dropFirst(Self.stashPrefix.count)))
            } else {
                nil
            }
            if let id, !items.contains(id) {
                items.append(id)
            }
        }
        self.items = items
    }

    var text: String {
        items.compactMap { id -> String? in
            switch id {
            case let .ref(name): name
            case let .stash(commit): Self.stashPrefix + commit
            case .remote: nil
            }
        }
        .map { $0 + "\n" }
        .joined()
    }

    /// Pins for branches and stashes this clone doesn't have are written back as they were, since
    /// the file is shared and another clone may have them.
    func write(to workTree: URL) throws {
        let folder = LocusFolder.url(in: workTree)
        let file = folder.appending(path: LocusFolder.pinsFile)
        if items.isEmpty {
            try? FileManager.default.removeItem(at: file)
            try LocusFolder.removeIfEmpty(folder)
            return
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file, options: .atomic)
        try LocusFolder.letPinsBeShared(in: folder)
    }
}
