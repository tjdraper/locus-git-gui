import AppKit
import SwiftUI

/// Shows Settings in an AppKit window. SwiftUI's `Settings` scene can only be opened from inside a
/// SwiftUI view, and the menu that opens it is AppKit.
final class SettingsWindowPresenter {
    private let gitChoice: GitChoiceStore
    private let updates: UpdateController
    private let fetchPreferences: FetchPreferences
    private lazy var window = makeWindow()

    init(gitChoice: GitChoiceStore, updates: UpdateController, fetchPreferences: FetchPreferences) {
        self.gitChoice = gitChoice
        self.updates = updates
        self.fetchPreferences = fetchPreferences
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Task { await gitChoice.refresh() }
    }

    /// Git can be installed, moved or removed while the app is in the background. The window is
    /// kept after it closes, so SwiftUI would go on refreshing for it; this only does while it shows.
    private func refreshGitWhenActive(for window: NSWindow) {
        Task { [weak self, weak window] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                guard let self, let window else { return }
                if window.isVisible {
                    await gitChoice.refresh()
                }
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let panes = SettingsTabController(panes: [
            (.general, NSHostingController(rootView: AnyView(GeneralSettingsPane(gitChoice: gitChoice)))),
            (.diffs, NSHostingController(rootView: AnyView(DiffSettingsPane(store: DiffSettingsStore())))),
            (.remotes, NSHostingController(rootView: AnyView(RemoteSettingsPane(preferences: fetchPreferences)))),
            (.updates, NSHostingController(rootView: AnyView(UpdateSettingsPane(updates: updates)))),
            (.license, NSHostingController(rootView: AnyView(LicenseSettingsPane(entitlements: .shared)))),
        ])
        let window = NSWindow(contentViewController: panes)
        window.styleMask = [.titled, .closable]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        panes.fitWindow(animated: false)
        refreshGitWhenActive(for: window)
        let fittedSize = window.contentRect(forFrameRect: window.frame).size
        RememberedWindowPlacement(autosaveName: "Settings").apply(to: window, initialContentSize: fittedSize)
        return window
    }
}
