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

/// A hosting view as tall as its content is at the width it's given. NSHostingView's own intrinsic
/// size is measured at the content's ideal width, which for a sentence is one line, so a sentence
/// wrapped in a narrow column spilled over the view's top and bottom.
private final class HeightForWidthHostingView<Content: View>: NSHostingView<Content> {
    private var measuredWidth: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        guard bounds.width > 0 else { return super.intrinsicContentSize }
        let proposal = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)
        let fitting = NSHostingController(rootView: rootView).sizeThatFits(in: proposal)
        return NSSize(width: NSView.noIntrinsicMetric, height: fitting.height)
    }

    override func layout() {
        super.layout()
        if bounds.width != measuredWidth {
            measuredWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }
}
