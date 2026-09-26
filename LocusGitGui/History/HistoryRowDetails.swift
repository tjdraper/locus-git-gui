import Foundation

/// What fits on the second line of a history row: its labels, then author · date · short hash.
/// The line is cut from the right, so the least useful part goes first: the hash, then the date,
/// then the author, and the labels last.
nonisolated struct HistoryRowDetails: Equatable {
    static let separator = " · "

    /// How many labels are shown. The rest are counted in one more label.
    let labelCount: Int
    let hiddenLabelCount: Int
    /// The author, date and hash that fit, with a separator in front when labels come before them.
    /// Nil when there's no room for any of it.
    let text: String?
    /// The author alone doesn't fit, and is cut with an ellipsis.
    let isTruncated: Bool

    struct Labels {
        let widths: [CGFloat]
        let spacing: CGFloat
        /// The width of the label counting the given number of hidden ones.
        let moreWidth: (Int) -> CGFloat
    }

    struct Parts {
        let author: String
        let date: String
        let hash: String
    }

    /// `measure` gives the width of a string in the line's font.
    static func fit(_ labels: Labels, _ parts: Parts, width: CGFloat, measure: (String) -> CGFloat) -> HistoryRowDetails {
        let labelWidths = labels.widths
        let labelSpacing = labels.spacing
        let moreWidth = labels.moreWidth
        let (author, date, hash) = (parts.author, parts.date, parts.hash)
        let labelCount = labelsThatFit(labelWidths, spacing: labelSpacing, moreWidth: moreWidth, width: width)
        let hiddenCount = labelWidths.count - labelCount
        let shownWidths = labelWidths.prefix(labelCount) + (hiddenCount > 0 ? [moreWidth(hiddenCount)] : [])
        let labelsWidth = shownWidths.reduce(0, +) + labelSpacing * CGFloat(max(shownWidths.count - 1, 0))
        let lead = shownWidths.isEmpty ? "" : separator
        let room = width - labelsWidth

        // A hash or date cut short would look like a whole one, so each is kept whole or left out.
        for parts in [[author, date, hash], [author, date]] {
            let text = lead + parts.joined(separator: separator)
            if measure(text) <= room {
                return HistoryRowDetails(labelCount: labelCount, hiddenLabelCount: hiddenCount, text: text, isTruncated: false)
            }
        }
        let authorText = lead + author
        let fits = measure(authorText) <= room
        // Too little room for even the start of a name is left empty rather than a lone ellipsis.
        let minimum = measure(lead + String(author.prefix(2)) + "…")
        return HistoryRowDetails(
            labelCount: labelCount,
            hiddenLabelCount: hiddenCount,
            text: fits || room >= minimum ? authorText : nil,
            isTruncated: !fits && room >= minimum
        )
    }

    /// All of them when they fit. Otherwise as many as fit beside the label counting the rest.
    private static func labelsThatFit(_ widths: [CGFloat], spacing: CGFloat, moreWidth: (Int) -> CGFloat, width: CGFloat) -> Int {
        func total(_ count: Int, hidden: Int) -> CGFloat {
            let shown = widths.prefix(count) + (hidden > 0 ? [moreWidth(hidden)] : [])
            return shown.reduce(0, +) + spacing * CGFloat(max(shown.count - 1, 0))
        }
        if total(widths.count, hidden: 0) <= width {
            return widths.count
        }
        for count in stride(from: widths.count - 1, to: 0, by: -1) where total(count, hidden: widths.count - count) <= width {
            return count
        }
        return 0
    }
}
