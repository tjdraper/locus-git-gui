import SwiftUI

struct CopyPathShortcutSection: View {
    @State private var copiesPathFromRoot = CopyPathShortcutPreference().copiesPathFromRoot

    var body: some View {
        Section {
            Picker(selection: $copiesPathFromRoot) {
                Text("Absolute path").tag(false)
                Text("Path from repository root").tag(true)
            } label: {
                Text("\(Self.shortcutText(of: .copyAbsolutePath)) copies")
                Text("The other path is \(Self.shortcutText(of: .copyPathFromRepositoryRoot)).")
            }
            .onChange(of: copiesPathFromRoot) {
                CopyPathShortcutPreference().copiesPathFromRoot = copiesPathFromRoot
                AppCommand.refreshMenuBarShortcuts()
            }
        } header: {
            Text("Copying a File’s Path")
        }
    }

    /// As the catalog has it, before Settings swaps the two.
    private static func shortcutText(of command: AppCommand) -> String {
        command.shortcut?.displayText ?? ""
    }
}
