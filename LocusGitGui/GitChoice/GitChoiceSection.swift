import AppKit
import SwiftUI

/// The checklist's Git step: what is in use, what else was found, and a way to pick any `git`.
struct GitChoiceSection: View {
    let store: GitChoiceStore
    @State private var isChanging = false
    @State private var startedInstallingTools = false
    @State private var typedPath = ""

    var body: some View {
        Section {
            chosenRow
            if showsAlternatives {
                alternativeRows
                otherGitRow
            }
        } header: {
            Text("Git")
        } footer: {
            Text("""
            Locus Git Gui runs the Git you already have, so your hooks, signing and settings work \
            the same as in Terminal.
            """)
            .foregroundStyle(.secondary)
        }
    }

    private var showsAlternatives: Bool {
        isChanging || store.chosenInstallation == nil
    }

    @ViewBuilder
    private var chosenRow: some View {
        switch store.availability {
        case .available:
            if let installation = store.chosenInstallation {
                LabeledContent {
                    if !isChanging {
                        Button("Change…") { isChanging = true }
                    }
                } label: {
                    Label {
                        Text("Git \(installation.version)")
                        Text(displayPath(installation.executableURL))
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        case let .missing(url):
            Label {
                Text("The Git this app was using is gone")
                Text("\(displayPath(url)) was moved or uninstalled. Choose another below.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
        case .notChosen, nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var alternativeRows: some View {
        if let result = store.searchResult {
            let alternatives = result.installations.filter { $0.executableURL != store.chosenInstallation?.executableURL }
            ForEach(alternatives, id: \.executableURL) { installation in
                LabeledContent {
                    Button("Use This Git") {
                        store.choose(installation)
                        isChanging = false
                    }
                } label: {
                    Text("Git \(installation.version)")
                    Text(installation.executableURL == result.terminalExecutableURL
                        ? "\(displayPath(installation.executableURL)), the one Terminal runs"
                        : displayPath(installation.executableURL))
                }
            }
            if result.installations.isEmpty {
                noGitFoundRow(commandLineToolsAreMissing: result.commandLineToolsAreMissing)
            }
        } else {
            LabeledContent("Looking for Git…") {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func noGitFoundRow(commandLineToolsAreMissing: Bool) -> some View {
        if commandLineToolsAreMissing {
            LabeledContent {
                Button("Install…") {
                    store.installCommandLineTools()
                    startedInstallingTools = true
                }
            } label: {
                Text("Git isn't installed")
                Text(startedInstallingTools
                    ? "Finish installing in the window that opened, then come back here."
                    : "Apple's Command Line Tools include Git. Installing them takes a few minutes.")
            }
        } else {
            LabeledContent("No Git was found") {
                EmptyView()
            }
        }
    }

    private var otherGitRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Another Git")
            HStack {
                TextField("Path to git", text: $typedPath, prompt: Text(verbatim: "/path/to/git"))
                    .labelsHidden()
                    // A grouped form draws fields without a border, which reads as plain text.
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(useTypedPath)
                    .onChange(of: typedPath) { store.dismissRejection() }
                Button("Use", action: useTypedPath)
                    .disabled(typedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Choose…", action: chooseFile)
            }
            Group {
                if let rejection = store.rejectedChoice {
                    Text(explanation(of: rejection))
                        .foregroundStyle(.red)
                } else {
                    Text("Type or paste the path to a git executable, or choose the file.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
    }

    private func useTypedPath() {
        guard !typedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            if await store.choose(typedPath: typedPath) {
                typedPath = ""
                isChanging = false
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.message = "Choose a git executable."
        panel.prompt = "Use This Git"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        // Keeps a link such as /opt/homebrew/bin/git as chosen, rather than the versioned file it
        // points to, which the next upgrade deletes.
        panel.resolvesAliases = false
        panel.directoryURL = URL(filePath: "/usr/local/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if await store.choose(fileAt: url) {
                typedPath = ""
                isChanging = false
            }
        }
    }

    private func explanation(of rejection: GitChoiceStore.Rejection) -> String {
        switch rejection {
        case .notAFullPath:
            "Enter the full path, starting with / or ~."
        case .probeFailed(.folder):
            "That's a folder. Enter the path to the git file inside it."
        case .probeFailed(.notExecutable):
            "There's no program at that path."
        case .probeFailed(.commandLineToolsMissing):
            "That's Apple's stand-in for Git, which needs the Command Line Tools installed first."
        case .probeFailed(.couldNotRun):
            "That program couldn't be run."
        case .probeFailed(.notGit):
            "That program didn't answer the way Git does."
        }
    }

    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
