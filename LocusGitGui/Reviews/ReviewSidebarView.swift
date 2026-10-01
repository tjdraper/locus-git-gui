import SwiftUI

/// The review window's left column: the two points, the files with a checkbox each, and how far
/// through the review is.
struct ReviewSidebarView: View {
    @Bindable var session: ReviewSession
    /// Commit… in either point's menu.
    let chooseCommit: (_ isBase: Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let review = session.review {
                ReviewPointsView(session: session, review: review, chooseCommit: chooseCommit)
                    .padding(10)
                Divider()
            }
            fileList
            Divider()
            footer
        }
    }

    private var fileList: some View {
        ScrollViewReader { proxy in
            List(selection: $session.selection) {
                overviewRow
                    .tag(ReviewSession.overviewTag)
                    .id(ReviewSession.overviewTag)
                ForEach(session.entries) { entry in
                    ReviewFileRow(entry: entry) { session.toggleCheck(entry.file.path) }
                        .tag(entry.file.path)
                        .id(entry.file.path)
                }
            }
            .listStyle(.sidebar)
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
                if let selection {
                    proxy.scrollTo(selection)
                }
            }
        }
    }

    private var overviewRow: some View {
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
