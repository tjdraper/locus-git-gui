import SwiftUI

/// The review window's left column: the review's comments, then its files with a checkbox each,
/// and how far through the review is. Several files can be picked to act on together.
struct ReviewSidebarView: View {
    /// What the file context menu does beyond checking files off, which belongs to the window.
    struct FileMenu {
        let commentOnFile: (String) -> Void
        let canShowChangesSince: (ReviewSession.Entry) -> Bool
        let toggleChangesSince: (String) -> Void
    }

    @Bindable var session: ReviewSession
    let fileMenu: FileMenu

    var body: some View {
        VStack(spacing: 0) {
            if let review = session.review, !review.missingPoints.isEmpty {
                ReviewMissingPointsNotice(review: review)
                    .padding(10)
                Divider()
            }
            fileList
            Divider()
            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var fileList: some View {
        ScrollViewReader { proxy in
            List(selection: $session.selection) {
                commentsRow
                    .tag(ReviewSession.overviewTag)
                    .id(ReviewSession.overviewTag)
                ForEach(session.entries) { entry in
                    ReviewFileRow(entry: entry) { session.setReviewed([entry.file.path], entry.state != .checked) }
                        .tag(entry.file.path)
                        .id(entry.file.path)
                }
            }
            .listStyle(.inset)
            .contextMenu(forSelectionType: String.self) { paths in
                menu(for: paths.subtracting([ReviewSession.overviewTag]))
            }
            .overlay {
                if let message = emptyMessage {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .onKeyPress(.space) {
                session.checkAndMoveOn()
                return .handled
            }
            .onChange(of: session.selection) { _, selection in
                if selection.count == 1, let path = selection.first {
                    proxy.scrollTo(path)
                }
            }
        }
    }

    private var commentsRow: some View {
        let unresolved = session.review?.unresolvedThreads ?? 0
        return HStack(spacing: 6) {
            Label("Comments", systemImage: "text.bubble")
            Spacer(minLength: 0)
            if unresolved > 0 {
                Text(unresolved.formatted())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(unresolved == 1 ? "1 unresolved comment" : "\(unresolved) unresolved comments")
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func menu(for paths: Set<String>) -> some View {
        let entries = session.entries.filter { paths.contains($0.file.path) }
        if !entries.isEmpty {
            let isReviewed = entries.allSatisfy { $0.state == .checked }
            Button(ReviewSelectionView.reviewedTitle(count: entries.count, isReviewed: isReviewed)) {
                session.setReviewed(paths, !isReviewed)
            }
            if entries.count == 1, let entry = entries.first {
                Button("Comment on File") { fileMenu.commentOnFile(entry.file.path) }
                if entry.state == .changedSinceReviewed, fileMenu.canShowChangesSince(entry) {
                    Toggle("Show Only Changes Since Reviewed", isOn: Binding(
                        get: { !session.showsWholeDiff.contains(entry.file.path) },
                        set: { _ in fileMenu.toggleChangesSince(entry.file.path) }
                    ))
                }
            }
            Divider()
            fileSystemItems(entries.map(\.file.path))
        }
    }

    /// As the diff's own file menu has them, for every file picked.
    @ViewBuilder
    private func fileSystemItems(_ paths: [String]) -> some View {
        let files = paths.map { WorkingTreeFile(path: $0, in: session.repository.workTree) }
        let existing = files.filter(\.exists)
        if files.count == 1, let file = existing.first {
            Button(AppCommand.openInEditor.title) { file.openInEditor() }
        }
        Button(AppCommand.revealChangedFileInFinder.title) {
            NSWorkspace.shared.activateFileViewerSelecting(existing.map(\.url))
        }
        .disabled(existing.isEmpty)
        Button(AppCommand.copyAbsolutePath.title) { copy(files.map(\.url.path)) }
        Button(AppCommand.copyPathFromRepositoryRoot.title) { copy(paths) }
    }

    private func copy(_ lines: [String]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private var emptyMessage: String? {
        if session.readFailure != nil, session.listing == nil {
            return "The review’s files couldn’t be read."
        }
        guard let listing = session.listing else { return nil }
        if listing.files.isEmpty {
            return "Nothing differs between these two points."
        }
        return session.entries.isEmpty && session.hidesChecked ? "Every file has been reviewed." : nil
    }

    /// A fixed height whatever it shows, so the list above doesn't move as the count changes.
    private var footer: some View {
        HStack(spacing: 8) {
            if let progress = session.review?.progress, session.listing != nil {
                if progress.isDone {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .help("Every file has been reviewed")
                }
                Text("\(progress.checked.formatted()) of \(progress.files.formatted()) reviewed")
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Toggle("Hide Reviewed", isOn: $session.hidesChecked)
                .toggleStyle(.checkbox)
                .controlSize(.small)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 30)
    }
}

/// The folder is cut from the left, so the part nearest the file stays.
private struct ReviewFileRow: View {
    let entry: ReviewSession.Entry
    let toggle: () -> Void

    var body: some View {
        let path = entry.file.path
        let folder = (path as NSString).deletingLastPathComponent
        HStack(spacing: 6) {
            Toggle("Reviewed", isOn: Binding(get: { entry.state == .checked }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(entry.state == .checked ? "Mark as Not Reviewed" : "Mark as Reviewed")
            VStack(alignment: .leading, spacing: 1) {
                Text((path as NSString).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .strikethrough(entry.file.change == .deleted)
                HStack(spacing: 0) {
                    if !folder.isEmpty {
                        Text("\(folder) · ")
                            .truncationMode(.head)
                            .layoutPriority(-1)
                    }
                    Text(description)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if entry.unresolvedThreads > 0 {
                Label(entry.unresolvedThreads.formatted(), systemImage: "text.bubble")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(entry.unresolvedThreads == 1 ? "1 unresolved comment" : "\(entry.unresolvedThreads) unresolved comments")
            }
            if entry.state == .changedSinceReviewed {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.orange)
                    .help("Changed since you reviewed it")
            }
        }
        .padding(.vertical, 2)
        .help(path)
    }

    private var description: String {
        if entry.state == .changedSinceReviewed {
            return "Changed since reviewed"
        }
        if entry.isUntracked {
            return "Untracked"
        }
        if let original = entry.file.originalPath {
            return "\(entry.file.change.title) from \((original as NSString).lastPathComponent)"
        }
        return entry.file.change.title
    }
}
