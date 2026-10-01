import SwiftUI

/// A name for a review. Left empty, the review is named for what it compares.
struct ReviewNameForm: View {
    let placeholder: String
    let finish: (String?) -> Void

    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(name: String, placeholder: String, finish: @escaping (String?) -> Void) {
        self.placeholder = placeholder
        self.finish = finish
        _name = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Review")
                .font(.headline)
            Text("Leave the name empty to name the review for what it compares.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Name", text: $name, prompt: Text(placeholder))
                .focused($isNameFocused)
                .autocorrectionDisabled()
            FormButtons(
                confirmTitle: "Rename",
                canConfirm: true,
                confirm: { finish(name.trimmingCharacters(in: .whitespacesAndNewlines)) },
                cancel: { finish(nil) }
            )
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            // SwiftUI ignores a focus change made in the same pass the view appears in.
            DispatchQueue.main.async {
                isNameFocused = true
            }
        }
    }
}
