import SwiftUI

/// A name for a new branch, or a new name for one, and for a new branch whether to check it out.
struct BranchNameForm: View {
    struct Result: Sendable {
        let name: String
        let checksOut: Bool
    }

    let title: String
    /// Says where the branch starts, or why a name is asked for.
    let message: String?
    let confirmTitle: String
    /// The other branches' names, which this one can't take.
    let takenNames: Set<String>
    /// Nil for a rename, which leaves checking out alone.
    let checksOutInitially: Bool?
    let finish: (Result?) -> Void

    @State private var name: String
    @State private var checksOut: Bool
    @FocusState private var isNameFocused: Bool

    init(
        title: String,
        message: String?,
        confirmTitle: String,
        name: String,
        takenNames: Set<String>,
        checksOut: Bool?,
        finish: @escaping (Result?) -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.takenNames = takenNames
        checksOutInitially = checksOut
        self.finish = finish
        _name = State(initialValue: name)
        _checksOut = State(initialValue: checksOut ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            if let message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Name", text: $name, prompt: Text("Branch name"))
                .focused($isNameFocused)
                .autocorrectionDisabled()
            if checksOutInitially != nil {
                Toggle("Check out the new branch", isOn: $checksOut)
            }
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            FormButtons(
                confirmTitle: confirmTitle,
                canConfirm: problem == nil && !trimmedName.isEmpty,
                confirm: { finish(Result(name: trimmedName, checksOut: checksOut)) },
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
        RefNameCheck.problem(with: trimmedName, kind: "branch", taken: takenNames)
    }
}
