import AppKit

/// Something to say about a file in place of, or above, its changes: that they were left out, that
/// it's binary, that only its mode changed. Changes that were left out have a button to show them.
final class DiffNoticeView: NSView {
    var onShow: (() -> Void)?
    var onShowDetails: (() -> Void)?

    private let message = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let showButton = NSButton(title: "Show Changes", target: nil, action: nil)
    private let detailsButton = NSButton(title: "Show Details", target: nil, action: nil)
    private var notice: DiffDocument.Notice?

    override init(frame: NSRect) {
        super.init(frame: frame)
        message.textColor = .secondaryLabelColor
        message.lineBreakMode = .byTruncatingTail
        message.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spinner.style = .spinning
        spinner.controlSize = .small
        for button in [showButton, detailsButton] {
            button.controlSize = .small
            button.bezelStyle = .push
            button.target = self
        }
        showButton.action = #selector(showChanges(_:))
        detailsButton.action = #selector(showDetails(_:))
        let stack = NSStackView(views: [spinner, message, showButton, detailsButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    func show(_ notice: DiffDocument.Notice) {
        guard notice != self.notice else { return }
        self.notice = notice
        message.stringValue = Self.text(for: notice)
        showButton.isHidden = !notice.offersToShow
        showButton.title = if case .failed = notice { "Try Again" } else { "Show Changes" }
        detailsButton.isHidden = if case .failed = notice { false } else { true }
        spinner.isHidden = notice != .reading
        if notice == .reading {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    private static func text(for notice: DiffDocument.Notice) -> String {
        switch notice {
        case let .modeChange(text): text + "."
        case .binary: "Binary file. Its changes can’t be shown as text."
        case let .tooLarge(lines): "\(lines.formatted()) changed lines, left out to keep the diff quick to read."
        case let .notRead(lines): "\(lines.formatted()) changed lines, left out since this diff is already long."
        case .reading: "Reading changes…"
        case let .failed(summary): summary
        case let .noChanges(text): text
        }
    }

    @objc private func showChanges(_: Any?) {
        onShow?()
    }

    @objc private func showDetails(_: Any?) {
        onShowDetails?()
    }
}
