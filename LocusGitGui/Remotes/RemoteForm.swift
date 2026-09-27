import AppKit
import SwiftUI

/// A remote's name and address, for adding one or editing one already there.
struct RemoteForm: View {
    let title: String
    let confirmTitle: String
    /// The other remotes' names, which this one can't take.
    let takenNames: Set<String>
    let onSave: (_ name: String, _ url: String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var url: String
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case url
    }

    init(
        title: String,
        confirmTitle: String,
        name: String,
        url: String,
        takenNames: Set<String>,
        onSave: @escaping (_ name: String, _ url: String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.takenNames = takenNames
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: name)
        _url = State(initialValue: url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Form {
                TextField("Name", text: $name)
                    .focused($focusedField, equals: .name)
                TextField("Address", text: $url, prompt: Text("https://example.com/owner/repository.git"))
                    .focused($focusedField, equals: .url)
            }
            .formStyle(.columns)
            .autocorrectionDisabled()
            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) {
                    onSave(trimmedName, trimmedURL)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil || trimmedName.isEmpty || trimmedURL.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            // SwiftUI ignores a focus change made in the same pass the view appears in.
            DispatchQueue.main.async {
                focusedField = name.isEmpty ? .name : .url
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Git refuses these itself, but saying so here keeps the sheet open to fix them.
    private var problem: String? {
        if takenNames.contains(trimmedName) {
            return "There’s already a remote named “\(trimmedName)”."
        }
        if trimmedName.contains(where: { $0.isWhitespace || "~^:?*[\\".contains($0) }) || trimmedName.hasPrefix("-")
            || trimmedName.contains("..") {
            return "A remote’s name can’t have spaces or ~ ^ : ? * [ \\ in it, or start with a hyphen."
        }
        return nil
    }

    static func present(_ form: RemoteForm, on window: NSWindow) -> NSWindow {
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        sheet.contentViewController = NSHostingController(rootView: form)
        window.beginSheet(sheet)
        return sheet
    }
}
