import SwiftUI

/// A thread of comments where it was left: on the review, on a file, or below the lines it's about
/// in the diff. A resolved thread folds down to a line until it's opened again.
struct ReviewThreadView: View {
    let session: ReviewSession
    let threadID: UUID
    /// Such as "Lines 12–14", and whether the lines have changed since.
    let label: String
    let isOutdated: Bool
    /// Set in from the diff's edges, to sit below the lines it's about.
    var insets = true
    var onHeightChange: ((CGFloat) -> Void)?

    @State private var reply = ""
    @State private var editing: UUID?
    @State private var edited = ""
    @State private var isExpanded = false

    private var thread: ReviewThread? {
        session.review?.threads.first { $0.id == threadID }
    }

    var body: some View {
        ReviewCommentCard(insets: insets, onHeightChange: onHeightChange) {
            if let thread {
                if thread.isResolved, !isExpanded {
                    folded(thread)
                } else {
                    expanded(thread)
                }
            }
        }
    }

    private func folded(_ thread: ReviewThread) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(label)
                .fontWeight(.medium)
            Text(thread.comments.first?.excerpt ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Button("Show") { isExpanded = true }
            Button("Reopen") { session.setResolved(threadID, false) }
        }
        .controlSize(.small)
    }

    private func expanded(_ thread: ReviewThread) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(label)
                    .fontWeight(.medium)
                if isOutdated {
                    Text("Outdated")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: .quaternarySystemFill), in: .capsule)
                        .help("The lines have changed since this was written")
                }
                Spacer(minLength: 8)
                if thread.isResolved {
                    Button("Hide") { isExpanded = false }
                }
                Button(thread.isResolved ? "Reopen" : "Resolve") {
                    session.setResolved(threadID, !thread.isResolved)
                    isExpanded = false
                }
            }
            .controlSize(.small)
            if isOutdated, case let .lines(anchor) = thread.place {
                Text(anchor.text.joined(separator: "\n"))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .quaternarySystemFill), in: .rect(cornerRadius: 4))
            }
            ForEach(thread.comments) { comment in
                commentView(comment)
                if comment.id != thread.comments.last?.id {
                    Divider()
                }
            }
            ReviewCommentField(text: $reply, prompt: "Reply", confirmTitle: "Reply", focusesOnAppear: false) {
                session.reply(to: threadID, body: reply)
                reply = ""
            }
        }
    }

    private func commentView(_ comment: ReviewComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.created.formatted(date: .abbreviated, time: .shortened))
                if comment.edited != nil {
                    Text("Edited")
                }
                Spacer()
                Menu {
                    Button("Edit") {
                        edited = comment.body
                        editing = comment.id
                    }
                    Button("Delete") { session.delete(comment.id, in: threadID) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if editing == comment.id {
                ReviewCommentField(text: $edited, prompt: "Comment", confirmTitle: "Save", focusesOnAppear: true) {
                    session.edit(comment.id, in: threadID, body: edited)
                    editing = nil
                } cancel: {
                    editing = nil
                }
            } else {
                MessageBodyView(text: comment.shownBody, showsMarkdown: true)
                    .textSelection(.enabled)
            }
        }
    }
}

/// A new thread being written, below the lines or at the top of the file it's for.
struct ReviewDraftView: View {
    let label: String
    let submit: (String) -> Void
    let cancel: () -> Void
    var onHeightChange: ((CGFloat) -> Void)?

    @State private var text = ""

    var body: some View {
        ReviewCommentCard(onHeightChange: onHeightChange) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .fontWeight(.medium)
                ReviewCommentField(text: $text, prompt: "Comment", confirmTitle: "Comment", focusesOnAppear: true) {
                    submit(text)
                } cancel: {
                    cancel()
                }
            }
        }
    }
}

/// A text area for a comment, which grows with what's written up to a point and scrolls after.
/// Return starts a new line, ⌘Return sends it, and Escape cancels.
struct ReviewCommentField: View {
    private static let lineHeight: CGFloat = 17
    private static let shownLines = 3 ... 12

    @Binding var text: String
    let prompt: String
    let confirmTitle: String
    let focusesOnAppear: Bool
    /// Counts up each time the field should take focus again.
    var focusRequest = 0
    let confirm: () -> Void
    var cancel: (() -> Void)?

    @FocusState private var isFocused: Bool

    private var canConfirm: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// While it's in use, at least a few lines, or more as they're typed, without counting where
    /// long ones wrap, which the area scrolls for. One line until then, so a reply below every
    /// thread doesn't crowd the diff.
    private var isInUse: Bool {
        isFocused || !text.isEmpty || cancel != nil
    }

    private var height: CGFloat {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let shown = isInUse ? min(max(lines, Self.shownLines.lowerBound), Self.shownLines.upperBound) : 1
        return CGFloat(shown) * Self.lineHeight + 12
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .scrollIndicators(isInUse ? .automatic : .never)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .frame(height: height)
                .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(prompt)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: isFocused ? .keyboardFocusIndicatorColor : .separatorColor))
                }
                .focused($isFocused)
                .onKeyPress(.escape) {
                    guard let cancel else { return .ignored }
                    cancel()
                    return .handled
                }
            if isInUse {
                HStack {
                    Text("Markdown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let cancel {
                        Button("Cancel", action: cancel)
                    }
                    Button(confirmTitle) {
                        guard canConfirm else { return }
                        confirm()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canConfirm)
                }
                .controlSize(.small)
            }
        }
        .onAppear {
            guard focusesOnAppear else { return }
            // SwiftUI ignores a focus change made in the same pass the view appears in.
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onChange(of: focusRequest) {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}

/// The box a thread sits in, which reports its height as it grows, since the diff lays it out at
/// a height of its own.
struct ReviewCommentCard<Content: View>: View {
    var insets = true
    var onHeightChange: ((CGFloat) -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
            .padding(.leading, insets ? 40 : 0)
            .padding(.trailing, insets ? 16 : 0)
            .padding(.vertical, insets ? 6 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                onHeightChange?(height)
            }
    }
}

extension ReviewComment {
    /// Each line as written, as GitHub and GitLab show a comment, where Markdown alone would run
    /// lines with a single break between them together. Lines in code blocks are left as they are.
    var shownBody: String {
        var isInCode = false
        return body.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                isInCode.toggle()
                return String(line)
            }
            return isInCode || line.isEmpty ? String(line) : line + "  "
        }
        .joined(separator: "\n")
    }

    /// The first line, with its inline Markdown applied, for where a comment is summed up.
    var excerpt: AttributedString {
        let line = body.split(separator: "\n").first.map(String.init) ?? ""
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: line, options: options)) ?? AttributedString(line)
    }
}
