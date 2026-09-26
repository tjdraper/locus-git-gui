import AppKit

/// One commit in the history: its place in the graph, its labels and subject on the first line, and
/// its author, date and short hash on the second.
final class HistoryRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("HistoryRow")
    static let height: CGFloat = 40

    /// More would push the subject out of a narrow column. The rest are counted in one more label.
    private static let visibleLabelLimit = 3
    private static let graphPadding: CGFloat = 4

    private let graph = CommitGraphView()
    private let labels = NSStackView()
    private let subject = NSTextField(labelWithString: "")
    private let details = NSTextField(labelWithString: "")
    private let shortHash = NSTextField(labelWithString: "")
    private var graphWidth: NSLayoutConstraint?
    private var subjectLeading: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        subject.lineBreakMode = .byTruncatingTail
        subject.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        details.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        details.textColor = .secondaryLabelColor
        details.lineBreakMode = .byTruncatingTail
        details.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        shortHash.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        shortHash.textColor = .secondaryLabelColor
        shortHash.setContentCompressionResistancePriority(.required, for: .horizontal)
        labels.orientation = .horizontal
        labels.spacing = 4
        labels.setHuggingPriority(.required, for: .horizontal)
        graph.setAccessibilityElement(false)
        textField = subject

        for view in [graph, labels, subject, details, shortHash] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let graphWidth = graph.widthAnchor.constraint(equalToConstant: 0)
        self.graphWidth = graphWidth
        let subjectLeading = subject.leadingAnchor.constraint(equalTo: labels.trailingAnchor)
        self.subjectLeading = subjectLeading
        NSLayoutConstraint.activate([
            graph.leadingAnchor.constraint(equalTo: leadingAnchor),
            graph.topAnchor.constraint(equalTo: topAnchor),
            graph.bottomAnchor.constraint(equalTo: bottomAnchor),
            graphWidth,
            labels.leadingAnchor.constraint(equalTo: graph.trailingAnchor, constant: Self.graphPadding),
            labels.centerYAnchor.constraint(equalTo: subject.centerYAnchor),
            subjectLeading,
            subject.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            subject.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            details.leadingAnchor.constraint(equalTo: graph.trailingAnchor, constant: Self.graphPadding),
            details.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            shortHash.leadingAnchor.constraint(greaterThanOrEqualTo: details.trailingAnchor, constant: 8),
            shortHash.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            shortHash.firstBaselineAnchor.constraint(equalTo: details.firstBaselineAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// Nil `graphRow` during a search, whose commits aren't joined by lines.
    func show(_ commit: Commit, graphRow: CommitGraphRow?, labels commitLabels: [CommitRefLabel]) {
        graph.row = graphRow
        graphWidth?.constant = graphRow.map { CGFloat($0.width) * CommitGraphView.laneWidth } ?? 0
        subject.stringValue = commit.subject.isEmpty ? "(No message)" : commit.subject
        subject.textColor = commit.subject.isEmpty ? .secondaryLabelColor : .labelColor
        let date = commit.author.date
        details.stringValue = "\(commit.author.name) · \(date.formatted(.relative(presentation: .named)))"
        details.toolTip = date.formatted(date: .complete, time: .shortened)
        shortHash.stringValue = String(commit.hash.prefix(7))

        labels.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for label in commitLabels.prefix(Self.visibleLabelLimit) {
            labels.addArrangedSubview(RefLabelView(label))
        }
        let hidden = commitLabels.dropFirst(Self.visibleLabelLimit)
        if !hidden.isEmpty {
            let more = RefLabelView(
                text: "+\(hidden.count)",
                kind: nil,
                description: hidden.map(RefLabelView.describe).joined(separator: ", ")
            )
            more.toolTip = hidden.map(\.name).joined(separator: "\n")
            labels.addArrangedSubview(more)
        }
        subjectLeading?.constant = commitLabels.isEmpty ? 0 : labels.spacing
        applyBackgroundStyle()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyBackgroundStyle() }
    }

    /// The fields only follow the row's selection colours when told, since they aren't the cell's
    /// own text field.
    private func applyBackgroundStyle() {
        let isEmphasized = backgroundStyle == .emphasized
        for field in [subject, details, shortHash] {
            field.cell?.backgroundStyle = backgroundStyle
        }
        graph.isEmphasized = isEmphasized
        for case let label as RefLabelView in labels.arrangedSubviews {
            label.isEmphasized = isEmphasized
        }
    }
}
