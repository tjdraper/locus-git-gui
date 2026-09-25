import AppKit
import SwiftUI

/// A borderless panel over the window the palette was opened from. It goes away as soon as it loses
/// focus, as a menu does.
final class CommandPalettePanel: NSPanel {
    enum KeyCommand {
        case moveUp
        case moveDown
        case choose
        /// Back to the step before, or away when there's none.
        case back
        /// Delete in an empty search field, which goes back a step but never closes the palette.
        case deleteBackward
    }

    static let cornerRadius: CGFloat = 16

    var onKeyCommand: ((KeyCommand) -> Bool)?
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: CommandPaletteView.width, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
    }

    func setRootView(_ rootView: some View) {
        let hostingView = NSHostingView(rootView: rootView)
        // The palette sizes itself to its results, through `setContentHeight(_:)`.
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = Self.cornerRadius
        hostingView.layer?.masksToBounds = true
        contentView = hostingView
    }

    /// Keeps the top edge where it is, so the search field stays put while the list below it changes.
    func setContentHeight(_ height: CGFloat) {
        guard height > 0, abs(frame.height - height) > 0.5 else { return }
        setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), display: true)
        invalidateShadow()
    }

    /// Borderless windows refuse key status by default, which would block typing in the search field.
    override var canBecomeKey: Bool {
        true
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// Caught here because the focused search field would otherwise take these keys itself.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !isComposingText, let command = Self.keyCommand(for: event), onKeyCommand?(command) == true {
            return
        }
        super.sendEvent(event)
    }

    /// While an input method is composing text, the arrows pick candidates and Return commits.
    private var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    private static func keyCommand(for event: NSEvent) -> KeyCommand? {
        guard event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]) else { return nil }
        switch event.keyCode {
        case upArrowKeyCode: return .moveUp
        case downArrowKeyCode: return .moveDown
        case returnKeyCode, enterKeyCode: return .choose
        case escapeKeyCode: return .back
        case deleteKeyCode: return .deleteBackward
        default: return nil
        }
    }

    private static let returnKeyCode: UInt16 = 36
    private static let deleteKeyCode: UInt16 = 51
    private static let escapeKeyCode: UInt16 = 53
    private static let enterKeyCode: UInt16 = 76
    private static let downArrowKeyCode: UInt16 = 125
    private static let upArrowKeyCode: UInt16 = 126
}
