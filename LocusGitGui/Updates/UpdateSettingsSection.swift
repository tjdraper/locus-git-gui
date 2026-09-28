import SwiftUI

struct UpdateSettingsSection: View {
    @Bindable var updates: UpdateController

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: $updates.automaticallyChecksForUpdates)
            Toggle(isOn: $updates.receivesBetaUpdates) {
                Text("Get beta updates")
                if updates.isRunningBeta {
                    Text("Stays on while you’re running a beta.")
                } else {
                    Text("Betas arrive more often and may break things.")
                }
            }
            .disabled(updates.isRunningBeta)
        } footer: {
            Text("""
            A new version never interrupts: the dashboard and each repository window offer it, \
            with a badge on the app’s icon in the Dock, until you’re ready. After two weeks, it asks.
            """)
            .foregroundStyle(.secondary)
        }
    }
}
