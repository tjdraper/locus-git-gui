import SwiftUI

/// The top of the working area: the message, whether to amend the last commit, and Commit.
struct CommitMessageView: View {
    let editor: CommitMessageEditor
    let focus: CommitMessageFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommitMessageFieldsView(editor: editor, focus: focus)
                .frame(height: CommitMessageFields.height)
            HStack(spacing: 8) {
                Toggle("Amend Last Commit", isOn: Binding(get: { editor.isAmending }, set: { _ in editor.toggleAmend?() }))
                    .toggleStyle(.checkbox)
                    .disabled(editor.isCommitting || !(editor.canAmend || editor.isAmending))
                Spacer(minLength: 8)
                if let hint = editor.hint {
                    Text(hint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if editor.isCommitting {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(editor.commitTitle) { editor.commit?() }
                    .disabled(!editor.canCommit)
                    .help("\(editor.commitTitle) (\(AppCommand.commitChanges.shortcut?.displayText ?? ""))")
            }
            if let note = editor.amendNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
