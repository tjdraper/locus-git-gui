import AppKit

/// An image file before and after its change, side by side, with each one's size.
final class DiffImagesView: NSView {
    enum State {
        case loading
        case loaded(before: DiffImage?, after: DiffImage?)
        case failed
    }

    private let before = DiffImageColumn(title: "Before")
    private let after = DiffImageColumn(title: "After")

    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = NSStackView(views: [before, after])
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func show(_ state: State) {
        switch state {
        case .loading:
            before.show(image: nil, caption: "Reading…")
            after.show(image: nil, caption: "Reading…")
        case .failed:
            before.show(image: nil, caption: "Couldn’t be read")
            after.show(image: nil, caption: "Couldn’t be read")
        case let .loaded(beforeSide, afterSide):
            show(beforeSide, in: before)
            show(afterSide, in: after)
        }
    }

    private func show(_ side: DiffImage?, in column: DiffImageColumn) {
        guard let side else {
            column.show(image: nil, caption: "None")
            return
        }
        let bytes = side.byteCount.formatted(.byteCount(style: .file))
        guard let pixelSize = side.pixelSize else {
            let reason = side.byteCount > DiffImage.byteLimit ? "too large to show" : "not an image macOS can read"
            column.show(image: nil, caption: "\(bytes), \(reason)")
            return
        }
        let image = side.image.map { NSImage(cgImage: $0, size: .zero) }
        column.show(image: image, caption: "\(Int(pixelSize.width)) × \(Int(pixelSize.height)) pixels, \(bytes)")
    }
}

/// One of the two images, with its size below.
private final class DiffImageColumn: NSView {
    private let imageView = NSImageView()
    private let caption = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        caption.textColor = .secondaryLabelColor
        caption.lineBreakMode = .byTruncatingTail
        imageView.imageScaling = .scaleProportionallyDown
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setAccessibilityLabel(title)
        let stack = NSStackView(views: [heading, imageView, caption])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func show(image: NSImage?, caption text: String) {
        imageView.image = image
        caption.stringValue = text
    }
}
