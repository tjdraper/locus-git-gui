import SwiftUI

/// Comments on the review as a whole, a field for a new one, and every comment on its files, each
/// leading to its file.
struct ReviewOverviewView: View {
    let session: ReviewSession
    let openFile: (String) -> Void
    let copyComments: () -> Void

    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Comments")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button(AppCommand.copyReviewComments.title, action: copyComments)
                        .disabled(session.review?.unresolvedThreads == 0)
                }
                ForEach(reviewThreads) { thread in
                    ReviewThreadView(session: session, threadID: thread.id, label: "Review", isOutdated: false, insets: false)
                }
                ReviewCommentField(
                    text: $text,
                    prompt: "Comment on the review",
                    confirmTitle: "Comment",
                    focusesOnAppear: false,
                    focusRequest: session.reviewCommentRequest
                ) {
                    session.startThread(.review, body: text.trimmingCharacters(in: .whitespacesAndNewlines))
                    text = ""
                }
                if !fileThreads.isEmpty {
                    Divider()
                    Text("On Files")
                        .font(.headline)
                    ForEach(fileThreads) { thread in
                        fileThreadRow(thread)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var reviewThreads: [ReviewThread] {
        session.review?.threads.filter { $0.place == .review } ?? []
    }

    private var fileThreads: [ReviewThread] {
        (session.review?.threads ?? []).filter { $0.place.path != nil }.sorted { ($0.place.path ?? "") < ($1.place.path ?? "") }
    }

    private func fileThreadRow(_ thread: ReviewThread) -> some View {
        let path = thread.place.path ?? ""
        let location: String = if case let .lines(anchor) = thread.place {
            "\(path), \(ReviewLineAnchor.label(anchor.lines).lowercased())"
        } else {
            path
        }
        return Button {
            openFile(path)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: thread.isResolved ? "checkmark.circle.fill" : "text.bubble")
                    .foregroundStyle(thread.isResolved ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Text(thread.comments.first?.excerpt ?? "")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if thread.comments.count > 1 {
                    Text(thread.comments.count == 2 ? "1 reply" : "\(thread.comments.count - 1) replies")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show in \((path as NSString).lastPathComponent)")
    }
}
