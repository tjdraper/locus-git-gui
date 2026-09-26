import AppKit

/// One row of the graph beside the history: the lines through it and the commit's dot. Rows sit
/// edge to edge, so each row's lines meet the next row's.
final class CommitGraphView: NSView {
    static let laneWidth: CGFloat = 14
    /// System colours, which adjust themselves for dark mode and stay apart from each other.
    static let palette: [NSColor] = [
        .systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemPink, .systemTeal, .systemRed, .systemIndigo,
    ]

    private static let lineWidth: CGFloat = 1.5
    private static let dotRadius: CGFloat = 4

    var row: CommitGraphRow? {
        didSet { needsDisplay = true }
    }

    /// The row is selected in a focused list, whose accent colour would swallow the dot's outline.
    var isEmphasized = false {
        didSet { needsDisplay = true }
    }

    static func color(_ index: Int) -> NSColor {
        index == CommitGraphRow.overflowColor ? .tertiaryLabelColor : palette[index % palette.count]
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_: NSRect) {
        guard let row else { return }
        let middle = bounds.midY
        for line in row.lines {
            let path = NSBezierPath()
            path.lineWidth = Self.lineWidth
            let fromX = x(line.fromLane)
            let toX = x(line.toLane)
            switch line.span {
            case .passing:
                path.move(to: NSPoint(x: fromX, y: 0))
                path.line(to: NSPoint(x: fromX, y: bounds.height))
            case .incoming:
                path.move(to: NSPoint(x: fromX, y: 0))
                curve(path, to: NSPoint(x: toX, y: middle), from: NSPoint(x: fromX, y: 0))
            case .outgoing:
                path.move(to: NSPoint(x: fromX, y: middle))
                curve(path, to: NSPoint(x: toX, y: bounds.height), from: NSPoint(x: fromX, y: middle))
            }
            Self.color(line.color).setStroke()
            path.stroke()
        }

        let center = NSPoint(x: x(row.lane), y: middle)
        let dot = NSBezierPath(ovalIn: NSRect(
            x: center.x - Self.dotRadius,
            y: center.y - Self.dotRadius,
            width: Self.dotRadius * 2,
            height: Self.dotRadius * 2
        ))
        Self.color(row.color).setFill()
        dot.fill()
        dot.lineWidth = Self.lineWidth
        (isEmphasized ? NSColor.alternateSelectedControlTextColor : NSColor.textBackgroundColor).setStroke()
        dot.stroke()
    }

    private func x(_ lane: Int) -> CGFloat {
        (CGFloat(lane) + 0.5) * Self.laneWidth
    }

    /// Straight down when the lane doesn't change, and an S-bend when it does.
    private func curve(_ path: NSBezierPath, to end: NSPoint, from start: NSPoint) {
        guard start.x != end.x else {
            path.line(to: end)
            return
        }
        let bend = (start.y + end.y) / 2
        path.curve(to: end, controlPoint1: NSPoint(x: start.x, y: bend), controlPoint2: NSPoint(x: end.x, y: bend))
    }
}
