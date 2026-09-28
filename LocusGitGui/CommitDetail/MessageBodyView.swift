import SwiftUI

/// A commit message's body as it's read: as Markdown, or as the plain text Git keeps.
struct MessageBodyView: View {
    private static let listIndent: CGFloat = 18
    private static let quoteIndent: CGFloat = 12

    let text: String
    let showsMarkdown: Bool

    var body: some View {
        if showsMarkdown {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(MessageMarkdown(text).blocks.enumerated()), id: \.offset) { _, block in
                    row(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Indented for the lists and quotes it's in, with its list item's marker in a column of its
    /// own, so the item's later paragraphs line up with its first.
    private func row(_ block: MessageMarkdown.Block) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if block.quoteDepth > 0 {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 2)
            }
            if block.listDepth > 0 {
                Text(block.listMarker ?? "")
                    .monospacedDigit()
                    .frame(width: Self.listIndent, alignment: .trailing)
            }
            content(block)
        }
        .foregroundStyle(block.quoteDepth > 0 ? .secondary : .primary)
        .padding(.leading, indent(block))
    }

    /// Deeper lists and quotes step in further. The first level's marker or bar is indent enough.
    private func indent(_ block: MessageMarkdown.Block) -> CGFloat {
        CGFloat(max(block.listDepth - 1, 0)) * Self.listIndent + CGFloat(max(block.quoteDepth - 1, 0)) * Self.quoteIndent
    }

    @ViewBuilder
    private func content(_ block: MessageMarkdown.Block) -> some View {
        switch block.kind {
        case .paragraph:
            Text(Self.styled(block.text))
        case let .heading(level):
            Text(Self.styled(block.text))
                .font(level == 1 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 4)
        case .code:
            Text(block.text)
                .font(.system(.callout, design: .monospaced))
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .quaternarySystemFill), in: .rect(cornerRadius: 4))
        case .rule:
            Divider()
        case .tableRow:
            Text(Self.styled(block.text))
                .font(.callout)
        }
    }

    /// Inline code in a fixed-width font on a faint fill. SwiftUI shows bold, italics and links
    /// from Markdown by itself, but leaves code as it finds it.
    private static func styled(_ text: AttributedString) -> AttributedString {
        var text = text
        for run in text.runs where run.inlinePresentationIntent?.contains(.code) == true {
            text[run.range].font = .system(.body, design: .monospaced)
            text[run.range].backgroundColor = Color(nsColor: .quaternarySystemFill)
        }
        return text
    }
}
