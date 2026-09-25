import AppKit

/// Asks, on the first launch of a full release after a beta, whether to keep getting betas.
struct BetaTrackExitWorkflow {
    let preference = UpdateChannelPreference()

    func offerIfNeeded() {
        preference.settleAtLaunch()
        guard preference.owesTrackChoice else { return }

        NSApp.activate()
        preference.chooseTrack(staysOnBetas: askToStayOnBetas())
    }

    private func askToStayOnBetas() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Keep getting beta updates?"
        alert.informativeText = """
        You’re now on a full release of Locus Git Gui. Betas arrive more often and may break \
        things. You can change this later in Settings.
        """
        alert.addButton(withTitle: "Stop Beta Updates")
        alert.addButton(withTitle: "Keep Beta Updates")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
