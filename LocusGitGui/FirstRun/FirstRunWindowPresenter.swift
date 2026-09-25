import AppKit
import SwiftUI

/// Shows the setup checklist on a first run, and again whenever the user asks for it.
final class FirstRunWindowPresenter: NSObject, NSWindowDelegate {
    private let gitChoice: GitChoiceStore
    private let onDone: () -> Void
    private let screenFit = ScreenFit()
    private var window: NSWindow?

    init(gitChoice: GitChoiceStore, onDone: @escaping () -> Void) {
        self.gitChoice = gitChoice
        self.onDone = onDone
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        screenFit.update(for: window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        screenFit.update(for: window)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        screenFit.keepOnScreen(window)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: FirstRunView(
                gitChoice: gitChoice,
                screenFit: screenFit,
                // Only Done finishes the first run. Closing the window or quitting, including the
                // relaunch after moving to Applications, brings the checklist back next launch.
                onDone: { [weak self] in
                    FirstRunStatus().markCompleted()
                    self?.window?.close()
                    self?.onDone()
                }
            )
        ))
        window.title = "Set Up Locus Git Gui"
        window.styleMask = [.titled, .closable]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.delegate = self
        screenFit.update(for: window)
        RememberedWindowPlacement(autosaveName: "Setup").apply(to: window)
        return window
    }
}
