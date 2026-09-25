import AppKit
import SwiftUI

/// Every setup step on one page. Each row shows the real state, so a Git installed or removed
/// while the checklist is open shows up when the user comes back to the app.
struct FirstRunView: View {
    let gitChoice: GitChoiceStore
    let screenFit: ScreenFit
    let onDone: () -> Void

    var body: some View {
        Form {
            Section {
                welcome
            }

            GitChoiceSection(store: gitChoice)

            if ApplicationsFolderMoveWorkflow.isAvailable {
                Section {
                    ApplicationsFolderRow()
                }
            }
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasUsableGit)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: .rect)
        }
        .frame(width: 520)
        // Only as tall as the steps need, unless the screen is shorter, when the steps scroll.
        .frame(maxHeight: screenFit.maxContentHeight)
        .fixedSize()
        .task {
            await gitChoice.refresh()
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                await gitChoice.refresh()
            }
        }
    }

    private var hasUsableGit: Bool {
        if case .available = gitChoice.availability {
            true
        } else {
            false
        }
    }

    private var welcome: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Locus Git Gui")
                    .font(.title2.bold())
                Text("Set up Locus Git Gui here. You can open this again from the Help menu.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
