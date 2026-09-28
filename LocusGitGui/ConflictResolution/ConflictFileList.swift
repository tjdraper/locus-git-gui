import SwiftUI

/// The conflict window's list of files. A file stays listed, marked resolved, once its conflict is,
/// so the list shows how far the whole operation has got. Conflicts arriving once none were left
/// are another operation's, and start the list again.
@Observable
final class ConflictFileList {
    struct Entry: Identifiable, Equatable {
        let path: String
        /// Nil once it's resolved.
        let conflict: RepositoryStatus.Conflict?

        var id: String {
            path
        }
    }

    private(set) var entries: [Entry] = []
    var names = ConflictSideNames(ours: "", theirs: "")
    var selection: String? {
        didSet {
            if selection != oldValue {
                onSelectionChange?(selection)
            }
        }
    }

    @ObservationIgnored var onSelectionChange: ((String?) -> Void)?
    /// Return in the list, which moves on to the result.
    @ObservationIgnored var onOpen: (() -> Void)?

    /// After every refresh. Files in the order Git lists them, which is by path.
    func show(_ conflicted: [(path: String, conflict: RepositoryStatus.Conflict)]) {
        let current = Set(conflicted.map(\.path))
        let isNewRound = !conflicted.isEmpty && conflictedPaths.isEmpty
        var entries = conflicted.map { Entry(path: $0.path, conflict: $0.conflict) }
        if !isNewRound {
            entries += self.entries.filter { !current.contains($0.path) }.map { Entry(path: $0.path, conflict: nil) }
        }
        entries.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        if entries != self.entries {
            self.entries = entries
        }
    }

    var conflictedPaths: [String] {
        entries.filter { $0.conflict != nil }.map(\.path)
    }

    /// The conflicted file after `path` in the list, or else the one before it, for when `path` is
    /// resolved.
    func conflictedFile(after path: String) -> String? {
        let index = entries.firstIndex { $0.path == path } ?? 0
        let after = entries[index...].dropFirst().first { $0.conflict != nil }
        return (after ?? entries[..<index].last { $0.conflict != nil })?.path
    }

    func description(of conflict: RepositoryStatus.Conflict?) -> String {
        let ours = "“\(names.ours)”"
        let theirs = "“\(names.theirs)”"
        return switch conflict {
        case .bothModified: "Changed on both sides"
        case .bothAdded: "Added on both sides"
        case .bothDeleted: "Deleted on both sides"
        case .deletedByUs: "Deleted in \(ours)"
        case .deletedByThem: "Deleted in \(theirs)"
        case .addedByUs: "Added in \(ours)"
        case .addedByThem: "Added in \(theirs)"
        case nil: "Resolved"
        }
    }
}

struct ConflictFileListView: View {
    @Bindable var list: ConflictFileList

    /// Follows the selection, which Next File and Previous File move from the menu bar.
    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $list.selection) {
                ForEach(list.entries) { entry in
                    row(entry)
                        .tag(entry.path)
                        .id(entry.path)
                }
            }
            .listStyle(.sidebar)
            .onKeyPress(.return) {
                list.onOpen?()
                return .handled
            }
            .onChange(of: list.selection) { _, selection in
                if let selection {
                    proxy.scrollTo(selection)
                }
            }
        }
    }

    /// The folder is cut from the left, so the part nearest the file stays, and before the conflict's
    /// description is.
    private func row(_ entry: ConflictFileList.Entry) -> some View {
        let folder = (entry.path as NSString).deletingLastPathComponent
        return Label {
            VStack(alignment: .leading, spacing: 1) {
                Text((entry.path as NSString).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 0) {
                    if !folder.isEmpty {
                        Text("\(folder) · ")
                            .truncationMode(.head)
                            .layoutPriority(-1)
                    }
                    Text(list.description(of: entry.conflict))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        } icon: {
            Image(systemName: entry.conflict == nil ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(entry.conflict == nil ? Color.green : Color.orange)
        }
        .help(entry.path)
    }
}
