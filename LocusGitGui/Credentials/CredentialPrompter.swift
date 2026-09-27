import AppKit
import SwiftUI

/// Asks what Git or SSH asked one command, in a sheet on the window the command was started from.
/// Cancelling the sheet cancels the command, since Git would otherwise carry on without the answer
/// and fail in a way that looks like something else went wrong.
final class CredentialPrompter {
    private let window: () -> NSWindow?
    private let activity: String
    private let cancelCommand: () -> Void
    private var lastPrompt: CredentialPrompt?

    /// `activity` says what the command is doing, such as “Fetching from “origin””.
    init(activity: String, window: @escaping () -> NSWindow?, cancelCommand: @escaping () -> Void) {
        self.window = window
        self.activity = activity
        self.cancelCommand = cancelCommand
    }

    /// Opens a channel on `server` for this prompter to answer, which keeps the prompter until the
    /// channel is closed once the command is done.
    func openChannel(on server: AskpassServer) -> AskpassChannel? {
        server.open { prompt in await self.answer(prompt) }
    }

    func answer(_ prompt: CredentialPrompt) async -> String? {
        guard let window = window(), !Task.isCancelled else {
            cancelCommand()
            return nil
        }
        let isRepeat = prompt == lastPrompt
        lastPrompt = prompt
        let presentation = CredentialSheetPresentation(parent: window)
        let answer = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                presentation.show(
                    CredentialPromptSheet(prompt: prompt, activity: activity, isRepeat: isRepeat) { [presentation] answer in
                        presentation.finish(with: answer)
                    },
                    resuming: continuation
                )
            }
        } onCancel: {
            Task { @MainActor in presentation.finish(with: nil) }
        }
        // A question withdrawn by Git or SSH, such as a finished touch of a security key, isn't the
        // user cancelling.
        if answer == nil, !Task.isCancelled {
            cancelCommand()
        }
        return answer
    }
}

/// One sheet and the answer it's waiting for, which it gives exactly once.
private final class CredentialSheetPresentation {
    private weak var parent: NSWindow?
    private var sheet: NSWindow?
    private var continuation: CheckedContinuation<String?, Never>?

    init(parent: NSWindow) {
        self.parent = parent
    }

    func show(_ view: CredentialPromptSheet, resuming continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
        guard let parent else {
            finish(with: nil)
            return
        }
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: view))
        self.sheet = sheet
        // AppKit queues it behind a sheet already showing, such as another command's question.
        parent.beginSheet(sheet)
    }

    func finish(with answer: String?) {
        guard let continuation else { return }
        self.continuation = nil
        if let sheet {
            // A sheet still queued behind another has no parent yet, and mustn't show later.
            (sheet.sheetParent ?? parent)?.endSheet(sheet)
        }
        continuation.resume(returning: answer)
    }
}
