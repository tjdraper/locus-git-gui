import AppKit
import SwiftUI

/// The subject and body of a commit message in one box, the subject above a hairline and the body
/// below. Both are in a fixed-width font, as Git and Terminal show a message, with a faint guide at
/// the length a subject should stay within and the width a body is usually wrapped to.
final class CommitMessageFields: NSView {
    static let height: CGFloat = 132
    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let subjectHeight: CGFloat = 28
    private static let cornerRadius: CGFloat = 6
    /// The body's text starts level with the subject's.
    private static let bodyInset = NSSize(width: 3, height: 6)

    var onSubjectChange: ((String) -> Void)?
    var onBodyChange: ((String) -> Void)?

    let subject = NSTextField()
    let body = CommitBodyTextView()
    private let bodyScroll = NSScrollView()
    private let advance: CGFloat
    private var isEditing = false
    private var firstResponderObservation: NSKeyValueObservation?

    override init(frame: NSRect) {
        advance = ("0" as NSString).size(withAttributes: [.font: Self.font]).width
        super.init(frame: frame)
        subject.font = Self.font
        subject.isBordered = false
        subject.drawsBackground = false
        subject.focusRingType = .none
        subject.placeholderString = "Subject"
        subject.lineBreakMode = .byClipping
        subject.cell?.isScrollable = true
        subject.cell?.usesSingleLineMode = true
        subject.delegate = self
        subject.setAccessibilityLabel("Subject")

        body.font = Self.font
        body.drawsBackground = false
        body.isRichText = false
        body.allowsUndo = true
        body.textContainerInset = Self.bodyInset
        body.isAutomaticQuoteSubstitutionEnabled = false
        body.isAutomaticDashSubstitutionEnabled = false
        body.isAutomaticTextReplacementEnabled = false
        body.isAutomaticSpellingCorrectionEnabled = false
        body.isVerticallyResizable = true
        body.isHorizontallyResizable = false
        body.autoresizingMask = [.width]
        body.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        body.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        body.textContainer?.widthTracksTextView = true
        body.delegate = self
        body.placeholder = "Body"
        body.setAccessibilityLabel("Body")
        bodyScroll.documentView = body
        bodyScroll.drawsBackground = false
        bodyScroll.hasVerticalScroller = true
        bodyScroll.autohidesScrollers = true

        addSubview(subject)
        addSubview(bodyScroll)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    /// Only what's changed, so the cursor stays where it is while the user types.
    func show(_ message: CommitMessage) {
        if subject.stringValue != message.subject {
            subject.stringValue = message.subject
        }
        if body.string != message.body {
            body.string = message.body
            body.needsDisplay = true
        }
    }

    override func layout() {
        super.layout()
        let subjectFieldHeight = subject.intrinsicContentSize.height
        subject.frame = NSRect(
            x: 6,
            y: ((Self.subjectHeight - subjectFieldHeight) / 2).rounded(),
            width: bounds.width - 12,
            height: subjectFieldHeight
        )
        bodyScroll.frame = NSRect(x: 1, y: Self.subjectHeight + 1, width: bounds.width - 2, height: bounds.height - Self.subjectHeight - 2)
        let content = bodyScroll.contentSize
        body.minSize = NSSize(width: 0, height: content.height)
        if body.frame.width != content.width {
            body.setFrameSize(NSSize(width: content.width, height: max(body.frame.height, content.height)))
        }
        body.guideX = body.textContainerInset.width + (body.textContainer?.lineFragmentPadding ?? 0)
            + CGFloat(CommitMessage.bodyGuide) * advance
        needsDisplay = true
    }

    /// Where the subject's text starts: the field's own inset, then the field editor's padding.
    private var subjectGuideX: CGFloat {
        let textStart = subject.cell?.drawingRect(forBounds: subject.bounds).minX ?? 2
        return subject.frame.minX + textStart + 2 + CGFloat(CommitMessage.subjectGuide) * advance
    }

    override func draw(_: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        NSColor.textBackgroundColor.setFill()
        box.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: Self.subjectHeight, width: bounds.width, height: 1).fill()
        NSColor.quaternaryLabelColor.setFill()
        NSRect(x: subjectGuideX.rounded(), y: 4, width: 1, height: Self.subjectHeight - 8).fill()
        box.lineWidth = isEditing ? 2 : 1
        (isEditing ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor).setStroke()
        box.stroke()
    }

    /// The box shows it has focus while either field does, since neither draws a ring of its own.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        firstResponderObservation = window?.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.updateEditing()
            }
        }
    }

    private func updateEditing() {
        let responder = window?.firstResponder
        let editing = responder === body || (responder as? NSTextView)?.delegate === subject
        guard editing != isEditing else { return }
        isEditing = editing
        needsDisplay = true
    }
}

extension CommitMessageFields: NSTextFieldDelegate, NSTextViewDelegate {
    /// A message pasted into the subject whole is split: its first line stays, and the rest goes to
    /// the start of the body.
    func controlTextDidChange(_: Notification) {
        let text = subject.stringValue
        if let newline = text.firstIndex(where: \.isNewline) {
            subject.stringValue = String(text[..<newline])
            let rest = text[newline...].trimmingCharacters(in: .newlines)
            body.string = body.string.isEmpty ? rest : rest + "\n" + body.string
            onBodyChange?(body.string)
        }
        onSubjectChange?(subject.stringValue)
    }

    /// Commit messages are plain text, where a curly quote or a corrected word would be a surprise.
    func controlTextDidBeginEditing(_ notification: Notification) {
        guard let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView else { return }
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
    }

    /// Return in the subject goes on to the body, as it would to the next line.
    func control(_: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        window?.makeFirstResponder(body)
        return true
    }

    func textDidChange(_: Notification) {
        onBodyChange?(body.string)
    }
}

/// The body's text view, which draws its placeholder and the guide behind the text.
final class CommitBodyTextView: NSTextView {
    var placeholder = ""
    var guideX: CGFloat = 0 {
        didSet { if guideX != oldValue { needsDisplay = true } }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        NSColor.quaternaryLabelColor.setFill()
        NSRect(x: guideX.rounded(), y: rect.minY, width: 1, height: rect.height).fill()
        guard string.isEmpty else { return }
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor,
        ])
    }
}

/// The fields in SwiftUI, kept in step with the editor's message both ways.
struct CommitMessageFieldsView: NSViewRepresentable {
    let editor: CommitMessageEditor

    func makeNSView(context _: Context) -> CommitMessageFields {
        let fields = CommitMessageFields()
        fields.onSubjectChange = { [editor] subject in editor.message.subject = subject }
        fields.onBodyChange = { [editor] body in editor.message.body = body }
        editor.subjectField = fields.subject
        editor.bodyTextView = fields.body
        fields.show(editor.message)
        return fields
    }

    /// Reads `externalChanges`, so a message loaded from outside the fields, such as for an amend,
    /// is shown.
    func updateNSView(_ fields: CommitMessageFields, context _: Context) {
        _ = editor.externalChanges
        fields.show(editor.message)
    }
}
