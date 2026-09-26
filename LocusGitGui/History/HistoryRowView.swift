import AppKit

/// One commit in the history: its place in the graph, its subject on the first line, and its
/// labels, author, date and short hash on the second. Every row is the same height, and the second
/// line gives up what matters least as the column narrows (see `HistoryRowDetails`).
final class HistoryRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("HistoryRow")
    static let height: CGFloat = 40

    private static let graphPadding: CGFloat = 4
    private static let trailingPadding: CGFloat = 8
    private static let verticalPadding: CGFloat = 4
    private static let labelSpacing: CGFloat = 4
    private static let detailsFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    /// Measures text as the details field will draw it, inset from its edges.
    private static let measuringCell: NSTextFieldCell = {
        let cell = NSTextFieldCell(textCell: "")
        cell.font = detailsFont
        return cell
    }()

    private let graph = CommitGraphView()
    private let subject = NSTextField(labelWithString: "")
    private let details = NSTextField(labelWithString: "")
    private var labels: [RefLabelView] = []
    private let more = RefLabelView(text: "", kind: nil, description: "")
    private var commitLabels: [CommitRefLabel] = []
    private var author = ""
    private var date = ""
    private var shortHash = ""
    private var graphWidth: CGFloat = 0

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        subject.lineBreakMode = .byTruncatingTail
        details.font = Self.detailsFont
        details.textColor = .secondaryLabelColor
        details.lineBreakMode = .byTruncatingTail
        graph.setAccessibilityElement(false)
        // Since macOS 14 a view draws outside its bounds unless told not to, which would put the
        // graph's lines through the subject beside it.
        graph.clipsToBounds = true
        textField = subject
        for view in [graph, subject, details, more] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    /// Nil `graphRow` during a search, whose commits aren't joined by lines. `graphLanes` is the
    /// same for every row, so their subjects line up.
    func show(_ commit: Commit, graphRow: CommitGraphRow?, graphLanes: Int, labels commitLabels: [CommitRefLabel]) {
        graph.row = graphRow
        graphWidth = graphRow == nil ? 0 : CGFloat(graphLanes) * CommitGraphView.laneWidth
        subject.stringValue = commit.subject.isEmpty ? "(No message)" : commit.subject
        subject.textColor = commit.subject.isEmpty ? .secondaryLabelColor : .labelColor
        let date = commit.author.date
        author = commit.author.name
        self.date = date.formatted(.relative(presentation: .named))
        shortHash = String(commit.hash.prefix(7))
        details.toolTip = date.formatted(date: .complete, time: .shortened)

        if commitLabels != self.commitLabels {
            self.commitLabels = commitLabels
            labels.forEach { $0.removeFromSuperview() }
            labels = commitLabels.map(RefLabelView.init)
            labels.forEach(addSubview)
        }
        applyBackgroundStyle()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        graph.frame = NSRect(x: 0, y: 0, width: graphWidth, height: bounds.height)
        let start = graphWidth + Self.graphPadding
        let width = max(bounds.width - start - Self.trailingPadding, 0)

        let subjectHeight = subject.intrinsicContentSize.height
        subject.frame = NSRect(x: start, y: Self.verticalPadding, width: width, height: subjectHeight)

        let fit = HistoryRowDetails.fit(
            HistoryRowDetails.Labels(widths: labels.map(\.intrinsicContentSize.width), spacing: Self.labelSpacing) { [more] count in
                more.text = "+\(count)"
                return more.intrinsicContentSize.width
            },
            HistoryRowDetails.Parts(author: author, date: date, hash: shortHash),
            width: width
        ) { text in
            Self.measuringCell.stringValue = text
            return Self.measuringCell.cellSize.width
        }
        let lineHeight = details.intrinsicContentSize.height
        let lineTop = bounds.height - Self.verticalPadding - lineHeight
        var x = start
        for (index, label) in labels.enumerated() {
            label.isHidden = index >= fit.labelCount
            guard !label.isHidden else { continue }
            x = place(label, at: x, lineTop: lineTop, lineHeight: lineHeight)
        }
        more.isHidden = fit.hiddenLabelCount == 0
        if !more.isHidden {
            let hidden = commitLabels.suffix(fit.hiddenLabelCount)
            more.text = "+\(fit.hiddenLabelCount)"
            more.toolTip = hidden.map(\.name).joined(separator: "\n")
            more.setAccessibilityLabel(hidden.map(RefLabelView.describe).joined(separator: ", "))
            x = place(more, at: x, lineTop: lineTop, lineHeight: lineHeight)
        }
        // Straight after the last label, since the text starts with its own separator.
        let detailsStart = x > start ? x - Self.labelSpacing : start
        details.stringValue = fit.text ?? ""
        details.isHidden = fit.text == nil
        details.frame = NSRect(x: detailsStart, y: lineTop, width: max(start + width - detailsStart, 0), height: lineHeight)
    }

    /// Centred on the line, and returns where the next thing on the line starts.
    private func place(_ label: RefLabelView, at x: CGFloat, lineTop: CGFloat, lineHeight: CGFloat) -> CGFloat {
        let size = label.intrinsicContentSize
        label.frame = NSRect(x: x, y: lineTop + (lineHeight - size.height) / 2, width: size.width, height: size.height)
        return x + size.width + Self.labelSpacing
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyBackgroundStyle() }
    }

    /// The details only follow the row's selection colours when told, since they aren't the cell's
    /// own text field.
    private func applyBackgroundStyle() {
        let isEmphasized = backgroundStyle == .emphasized
        details.cell?.backgroundStyle = backgroundStyle
        graph.isEmphasized = isEmphasized
        for label in labels + [more] {
            label.isEmphasized = isEmphasized
        }
    }
}
