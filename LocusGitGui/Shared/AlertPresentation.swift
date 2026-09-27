import AppKit

/// An alert as a sheet on a window, or on its own when there's no window to put it on.
enum AlertPresentation {
    static func run(_ alert: NSAlert, on window: NSWindow?) async -> NSApplication.ModalResponse {
        guard let window else {
            return alert.runModal()
        }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
    }
}
