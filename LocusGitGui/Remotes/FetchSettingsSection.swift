import SwiftUI

/// The same choices as the Remote menu, with how often an automatic fetch happens.
struct FetchSettingsSection: View {
    @Bindable var preferences: FetchPreferences

    var body: some View {
        Section {
            Toggle(isOn: $preferences.fetchesAutomatically) {
                Text("Fetch automatically")
                Text("Only updates remote branches. Your own branches and files are never changed.")
            }
            Picker("Fetch every", selection: $preferences.automaticIntervalMinutes) {
                ForEach(FetchPreferences.automaticIntervals, id: \.self) { minutes in
                    Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                }
            }
            .disabled(!preferences.fetchesAutomatically)
        } footer: {
            Text("""
            Each open repository fetches from every remote a few seconds after it opens, and then \
            at this interval. It never asks for a password; a remote that needs one shows a warning \
            in the toolbar instead.
            """)
            .foregroundStyle(.secondary)
        }

        Section {
            Toggle(isOn: $preferences.options.prunes) {
                Text("Prune when fetching")
                Text("Removes remote branches that were deleted on the remote.")
            }
            Toggle(isOn: $preferences.options.fetchesTags) {
                Text("Fetch tags when fetching")
                Text("Fetches every tag, not only those on the branches fetched.")
            }
        } footer: {
            Text("Fetch follows these, and the Remote menu has a Fetch for each choice.")
                .foregroundStyle(.secondary)
        }
    }
}
