import AppKit
import SwiftUI

/// The panes along the top of the Settings window.
enum SettingsPane: String, CaseIterable {
    case general
    case diffs
    case remotes
    case updates
    case license

    var title: String {
        switch self {
        case .general: "General"
        case .diffs: "Diffs"
        case .remotes: "Remotes"
        case .updates: "Updates"
        case .license: "License"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .diffs: "plus.forwardslash.minus"
        case .remotes: "network"
        case .updates: "arrow.down.circle"
        case .license: "checkmark.seal"
        }
    }
}

struct GeneralSettingsPane: View {
    let gitChoice: GitChoiceStore

    var body: some View {
        SettingsForm {
            GitChoiceSection(store: gitChoice)
            if case let .launchEnvironment(fallback) = gitChoice.environmentSource {
                Section {
                    ShellEnvironmentNotice(fallback: fallback)
                }
            }
            CopyPathShortcutSection()
        }
    }
}

struct DiffSettingsPane: View {
    let store: DiffSettingsStore

    var body: some View {
        SettingsForm {
            DiffSettingsSection(store: store)
        }
    }
}

struct RemoteSettingsPane: View {
    let preferences: FetchPreferences

    var body: some View {
        SettingsForm {
            FetchSettingsSection(preferences: preferences)
        }
    }
}

struct UpdateSettingsPane: View {
    let updates: UpdateController

    var body: some View {
        SettingsForm {
            UpdateSettingsSection(updates: updates)
        }
    }
}

struct LicenseSettingsPane: View {
    let entitlements: EntitlementStore

    var body: some View {
        SettingsForm {
            LicenseSettingsSection(entitlements: entitlements)
        }
    }
}

/// Every pane is the same width, and as tall as its settings, so the window changes height alone
/// as the panes change.
private struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 520)
        .fixedSize()
    }
}
