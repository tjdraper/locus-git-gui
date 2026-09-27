import SwiftUI

/// A stash's message, and whether it takes untracked files too.
struct StashForm: View {
    struct Result: Sendable {
        let message: String
        let includesUntracked: Bool
    }

    let finish: (Result?) -> Void

    @State private var message = ""
    @State private var includesUntracked: Bool
    @FocusState private var isMessageFocused: Bool

    init(includesUntracked: Bool, finish: @escaping (Result?) -> Void) {
        self.finish = finish
        _includesUntracked = State(initialValue: includesUntracked)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stash Changes")
                .font(.headline)
            Text("Staged and unstaged changes are put aside, and the files go back to the last commit.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Message", text: $message, prompt: Text("Message (optional)"))
                .focused($isMessageFocused)
            Toggle("Include untracked files", isOn: $includesUntracked)
            FormButtons(
                confirmTitle: "Stash",
                canConfirm: true,
                confirm: {
                    finish(Result(message: message.trimmingCharacters(in: .whitespacesAndNewlines), includesUntracked: includesUntracked))
                },
                cancel: { finish(nil) }
            )
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            // SwiftUI ignores a focus change made in the same pass the view appears in.
            DispatchQueue.main.async {
                isMessageFocused = true
            }
        }
    }
}
