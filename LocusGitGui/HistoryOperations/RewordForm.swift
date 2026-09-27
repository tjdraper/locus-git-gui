import SwiftUI

/// A commit's new message, with the subject and body apart as the working area writes them.
struct RewordForm: View {
    /// Names the commit, and says what rewording it does to the commits after it.
    let message: String
    let finish: (CommitMessage?) -> Void

    @State private var subject: String
    @State private var bodyText: String
    @FocusState private var isSubjectFocused: Bool

    init(message: String, current: CommitMessage, finish: @escaping (CommitMessage?) -> Void) {
        self.message = message
        self.finish = finish
        _subject = State(initialValue: current.subject)
        _bodyText = State(initialValue: current.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reword Commit")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Subject", text: $subject, prompt: Text("Subject"))
                .font(.system(.body, design: .monospaced))
                .focused($isSubjectFocused)
            TextEditor(text: $bodyText)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .frame(height: 140)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
            FormButtons(
                confirmTitle: "Reword",
                canConfirm: newMessage.canCommit,
                confirm: { finish(newMessage) },
                cancel: { finish(nil) }
            )
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            // SwiftUI ignores a focus change made in the same pass the view appears in.
            DispatchQueue.main.async {
                isSubjectFocused = true
            }
        }
    }

    private var newMessage: CommitMessage {
        CommitMessage(subject: subject, body: bodyText)
    }
}
