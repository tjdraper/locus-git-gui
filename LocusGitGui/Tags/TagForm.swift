import SwiftUI

/// A new tag's name, and a message, which makes it an annotated tag.
struct TagForm: View {
    struct Result: Sendable {
        let name: String
        let message: String
    }

    /// Says which commit the tag goes on.
    let message: String
    let takenNames: Set<String>
    let finish: (Result?) -> Void

    @State private var name = ""
    @State private var annotation = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Tag")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Name", text: $name, prompt: Text("Tag name, such as v1.0"))
                .focused($isNameFocused)
                .autocorrectionDisabled()
            TextField("Message", text: $annotation, prompt: Text("Message (optional)"), axis: .vertical)
                .lineLimit(3 ... 6)
            Text("A tag with a message is annotated, with your name and the date. Without one, it’s a lightweight tag.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            FormButtons(
                confirmTitle: "Create Tag",
                canConfirm: problem == nil && !trimmedName.isEmpty,
                confirm: { finish(Result(name: trimmedName, message: annotation.trimmingCharacters(in: .whitespacesAndNewlines))) },
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

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var problem: String? {
        RefNameCheck.problem(with: trimmedName, kind: "tag", taken: takenNames)
    }
}
