import AppKit
import SwiftUI

/// The bars above the history: a fetch, pull or push in progress, and an operation stopped partway
/// or the notice a destructive command leaves. One view, so they stack without overlapping the
/// history as each grows and shrinks.
struct HistoryBars: View {
    let remote: RemoteProgress
    let operation: OperationStatus

    var body: some View {
        VStack(spacing: 0) {
            RemoteProgressBar(model: remote)
            OperationBar(status: operation)
        }
    }

    static func make(_ remote: RemoteProgress, _ operation: OperationStatus) -> NSView {
        let view = HeightForWidthHostingView(rootView: HistoryBars(remote: remote, operation: operation))
        view.sizingOptions = [.intrinsicContentSize]
        return view
    }
}
