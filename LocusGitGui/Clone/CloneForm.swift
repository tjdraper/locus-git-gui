import SwiftUI

/// The Clone Repository window's fields, and while it clones, how far it has got.
struct CloneForm: View {
    @Bindable var session: CloneSession
    let progress: RemoteProgress
    let chooseParentFolder: () -> Void
    let clone: () -> Void
    let close: () -> Void

    @FocusState private var isAddressFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                TextField("Address", text: $session.address, prompt: Text("https://example.com/owner/repository.git"))
                    .focused($isAddressFocused)
                LabeledContent("Where") {
                    HStack {
                        Text((session.parentFolder.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(session.parentFolder.path)
                        Button("Choose…", action: chooseParentFolder)
                    }
                }
                TextField("Folder Name", text: Binding(get: { session.folderName }, set: session.setFolderName))
                Toggle("Include submodules", isOn: $session.includesSubmodules)
            }
            .formStyle(.columns)
            .autocorrectionDisabled()
            .disabled(isCloning)
            status
            HStack {
                Spacer()
                Button(isCloning ? "Stop" : "Cancel") {
                    if let running = progress.running {
                        running.cancel()
                    } else {
                        close()
                    }
                }
                .keyboardShortcut(.cancelAction)
                Button("Clone", action: clone)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!session.canClone || isCloning)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            // SwiftUI ignores a focus change made in the same pass the view appears in.
            DispatchQueue.main.async {
                isAddressFocused = true
            }
        }
    }

    private var isCloning: Bool {
        progress.running != nil
    }

    /// How far the clone has got while it runs, and otherwise why it can't start or where it goes.
    @ViewBuilder
    private var status: some View {
        if let running = progress.running {
            VStack(alignment: .leading, spacing: 4) {
                Text(running.progress?.summary ?? running.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let fraction = running.progress?.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
        } else if let problem = session.problem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if !session.folderName.isEmpty {
            HStack(spacing: 4) {
                Text("Clones into")
                    .layoutPriority(1)
                Text((session.destination.path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}
