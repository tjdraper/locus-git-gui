import AppKit
import SwiftUI

/// A hosting view as tall as its content is at the width it's given. NSHostingView's own intrinsic
/// size is measured at the content's ideal width, which for a sentence is one line, so a sentence
/// wrapped in a narrow column spilled over the view's top and bottom.
final class HeightForWidthHostingView<Content: View>: NSHostingView<Content> {
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
