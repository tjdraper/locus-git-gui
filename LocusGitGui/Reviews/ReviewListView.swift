import SwiftUI

/// A repository's reviews, the most recently changed first. Clicking one opens it, and the rest of
/// what can be done with one is in its context menu.
struct ReviewListView: View {
    let list: ReviewList
    /// Nil in the window, which has nowhere further to open into.
    var openInWindow: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if list.isEmpty {
                ContentUnavailableView {
                    Label("No Reviews", systemImage: "checklist")
                } description: {
                    Text(
                        "A review lists what differs between two points, such as a branch and the one it will merge into, "
                            + "and keeps track of each file you check off."
                    )
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(list.reviews) { review in
                        ReviewListRow(review: review) { list.onOpen?(review.id) }
                            .contextMenu {
                                Button("Open") { list.onOpen?(review.id) }
                                Divider()
                                Button("Rename…") { list.onRename?(review.id) }
                                Button("Delete…") { list.onDelete?(review.id) }
                            }
                    }
                    if list.olderCount > 0 {
                        Toggle(olderTitle, isOn: Binding(get: { list.showsOlder }, set: { list.showsOlder = $0 }))
                            .toggleStyle(.checkbox)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var olderTitle: String {
        let count = list.olderCount
        return count == 1
            ? "Show 1 review not opened in \(ReviewListing.recentDays) days"
            : "Show \(count.formatted()) reviews not opened in \(ReviewListing.recentDays) days"
    }

    private var header: some View {
        HStack {
            Text("Reviews")
                .font(.headline)
            Spacer()
            if let openInWindow {
                Button("Open in Window", systemImage: "macwindow", action: openInWindow)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Open in Window")
            }
            Button(AppCommand.newReview.title) { list.onNewReview?() }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }
}

private struct ReviewListRow: View {
    let review: Review
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 8) {
                statusIcon
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Group {
                        if review.name != nil {
                            Text(review.comparison)
                                .truncationMode(.middle)
                        }
                        Text(details)
                    }
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.callout)
        .padding(.vertical, 3)
        .help(review.comparison)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if !review.missingPoints.isEmpty {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .help("A branch this review follows is gone")
        } else if review.progress.isDone {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .help("Every file has been reviewed")
        } else if review.progress.changedSinceReviewed > 0 {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.orange)
                .padding(.top, 4)
                .help("Files changed since you reviewed them")
        } else {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
        }
    }

    private var details: String {
        let progress = review.progress
        var parts: [String] = []
        if review.revision == nil {
            parts.append("Not read yet")
        } else if progress.files == 0 {
            parts.append("No changes")
        } else if progress.isDone {
            parts.append("Done")
        } else {
            parts.append("\(progress.checked.formatted()) of \(progress.files.formatted()) reviewed")
        }
        if progress.changedSinceReviewed > 0 {
            parts.append("\(progress.changedSinceReviewed.formatted()) changed")
        }
        let unresolved = review.unresolvedThreads
        if unresolved > 0 {
            parts.append(unresolved == 1 ? "1 unresolved comment" : "\(unresolved.formatted()) unresolved comments")
        }
        parts.append(review.lastChanged.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}
