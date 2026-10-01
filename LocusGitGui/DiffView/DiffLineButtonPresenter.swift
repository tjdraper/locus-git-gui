import AppKit

/// What a button beside a line does, such as starting a comment on it.
struct DiffLineButton {
    let symbol: String
    let title: String
    let perform: (DiffLineTarget) -> Void
}

/// Shows the line button beside the line under the pointer, over the start of its line numbers,
/// as GitHub does. It's in the diff's own coordinates, so it scrolls with its line.
final class DiffLineButtonPresenter: NSObject {
    var action: DiffLineButton? {
        didSet {
            button.image = action.flatMap { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: $0.title) }
            button.toolTip = action?.title
            if action == nil {
                hide()
            }
        }
    }

    private weak var controller: DiffViewController?
    private let button = NSButton(title: "", target: nil, action: nil)
    private var target: DiffLineTarget?

    init(controller: DiffViewController) {
        self.controller = controller
        super.init()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.contentTintColor = .controlAccentColor
        button.target = self
        button.action = #selector(press(_:))
        button.isHidden = true
        controller.canvas.onHover = { [weak self] block, side in self?.hover(block: block, side: side) }
    }

    private func hover(block: Int?, side: Int) {
        guard action != nil, let controller, let content = controller.canvas.content, let block,
              case let .lines(file, _, _, _) = content.document.blocks[block],
              let target = DiffLineTarget(blocks: block ... block, side: side, document: content.document, files: content.files)
        else {
            hide()
            return
        }
        self.target = target
        let sides = content.layout.sides(forFile: file)
        let lineSide = sides[min(side, sides.count - 1)]
        let height = content.layout.metrics.lineHeight
        button.frame = NSRect(x: lineSide.minX + 2, y: content.layout.top(of: block), width: height + 4, height: height)
        if button.superview !== controller.canvas {
            controller.canvas.addSubview(button)
        }
        button.isHidden = false
    }

    private func hide() {
        button.isHidden = true
        target = nil
    }

    @objc private func press(_: Any?) {
        guard let target else { return }
        action?.perform(target)
        hide()
    }
}
