import SwiftUI

struct DisplayNameForm: View {
    let folderName: String
    /// Git already tracks the `.locus` folder, so the name is shared whatever is chosen here.
    let isTracked: Bool
    let onSave: (RepositoryDisplayName) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var isShared: Bool
    @FocusState private var isNameFocused: Bool

    init(
        folderName: String,
        current: RepositoryDisplayName,
        isTracked: Bool,
        onSave: @escaping (RepositoryDisplayName) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.folderName = folderName
        self.isTracked = isTracked
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: current.name ?? "")
        _isShared = State(initialValue: current.isShared || isTracked)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display Name for “\(folderName)”")
                .font(.headline)
            TextField("Display Name", text: $name, prompt: Text(folderName))
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
            Toggle("Share through Git", isOn: $isShared)
                .disabled(isTracked)
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(RepositoryDisplayName(name: name, isShared: isShared))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            // SwiftUI ignores a focus change made in the same pass the view appears in.
            DispatchQueue.main.async {
                isNameFocused = true
            }
        }
    }

    private var explanation: String {
        if isTracked {
            return """
            The name is kept in a .locus folder at the top of the repository. Git already tracks \
            that folder, so everyone who clones the repository gets the name.
            """
        }
        if isShared {
            return """
            The name is kept in a .locus folder at the top of the repository. Commit the folder and \
            everyone who clones the repository gets the name.
            """
        }
        return """
        The name is kept in a .locus folder at the top of the repository, which Git ignores. Only \
        this copy of the repository has the name.
        """
    }
}
