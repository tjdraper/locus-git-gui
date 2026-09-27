import AppKit
import SwiftUI

/// A SwiftUI form as a sheet on a window, waited for until it's confirmed or cancelled.
enum FormSheet {
    /// `make` builds the form around the closure it calls once: with what was confirmed, or nil
    /// when cancelled.
    static func ask<Result: Sendable>(on window: NSWindow, _ make: (@escaping (Result?) -> Void) -> some View) async -> Result? {
        await withCheckedContinuation { continuation in
            let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
            let once = Once()
            let finish = { [weak window] (result: Result?) in
                guard once.claim() else { return }
                window?.endSheet(sheet)
                continuation.resume(returning: result)
            }
            sheet.contentViewController = NSHostingController(rootView: make(finish))
            window.beginSheet(sheet)
        }
    }

    /// Keeps a second click on the confirm button from finishing the form twice.
    private final class Once {
        private var isClaimed = false

        func claim() -> Bool {
            defer { isClaimed = true }
            return !isClaimed
        }
    }
}

/// The buttons at the bottom of every form: Return confirms and Escape cancels.
struct FormButtons: View {
    let confirmTitle: String
    let canConfirm: Bool
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
            Button(confirmTitle, action: confirm)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm)
        }
    }
}
