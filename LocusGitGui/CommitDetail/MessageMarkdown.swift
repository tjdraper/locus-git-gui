import Foundation

/// A commit message's body read as Markdown, as blocks to show one under another: paragraphs,
/// headings, code, rules and table rows, each with the list and quote it's in. Foundation's own
/// parser supplies the structure, so no package is needed for it.
nonisolated struct MessageMarkdown: Equatable, Sendable {
    enum BlockKind: Equatable, Sendable {
        case paragraph
        case heading(level: Int)
        case code
        case rule
        /// Its cells run together, divided by a bar.
        case tableRow
    }

    struct Block: Equatable, Sendable, Identifiable {
        let id: Int
        let kind: BlockKind
        var text: AttributedString
        /// “•” or “2.” on the first block of a list item, and nil on the rest of it.
        let listMarker: String?
        let listDepth: Int
        let quoteDepth: Int
    }

    /// Links a message can hold that are safe to open from it. Anything else, such as a file or
    /// an app's own scheme, stays as its text.
    private static let linkSchemes: Set<String> = ["http", "https", "mailto"]

    let blocks: [Block]

    init(_ markdown: String) {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            blocks = [Block(id: 0, kind: .paragraph, text: AttributedString(markdown), listMarker: nil, listDepth: 0, quoteDepth: 0)]
            return
        }
        var blocks: [Block] = []
        var markedItems: Set<Int> = []
        var lastCell: Int?
        for run in parsed.runs {
            var text = AttributedString(parsed[run.range])
            if let link = run.link, !Self.linkSchemes.contains(link.scheme?.lowercased() ?? "") {
                text.link = nil
            }
            let components = run.presentationIntent?.components ?? []
            let key = Self.blockComponent(components)
            if !blocks.isEmpty, blocks.last?.id == key?.identity ?? -1 {
                let cell = components.first { if case .tableCell = $0.kind { true } else { false } }?.identity
                if let cell, let lastCell, cell != lastCell {
                    blocks[blocks.count - 1].text += AttributedString(" │ ")
                }
                lastCell = cell
                blocks[blocks.count - 1].text += text
                continue
            }
            lastCell = components.first { if case .tableCell = $0.kind { true } else { false } }?.identity
            blocks.append(Self.block(key, components: components, text: text, markedItems: &markedItems))
        }
        self.blocks = blocks.map { block in
            guard block.kind == .code else { return block }
            var block = block
            while block.text.characters.last?.isNewline == true {
                block.text.removeSubrange(block.text.index(beforeCharacter: block.text.endIndex) ..< block.text.endIndex)
            }
            return block
        }
    }

    /// The component a run's block is made from: its paragraph, heading, code or rule, or for a
    /// table cell, the row it's in.
    private static func blockComponent(_ components: [PresentationIntent.IntentType]) -> PresentationIntent.IntentType? {
        if components.first.map({ if case .tableCell = $0.kind { true } else { false } }) == true {
            return components.first { component in
                switch component.kind {
                case .tableRow, .tableHeaderRow: true
                default: false
                }
            }
        }
        return components.first
    }

    private static func block(
        _ key: PresentationIntent.IntentType?,
        components: [PresentationIntent.IntentType],
        text: AttributedString,
        markedItems: inout Set<Int>
    ) -> Block {
        let kind: BlockKind = switch key?.kind {
        case let .header(level): .heading(level: level)
        case .codeBlock: .code
        case .thematicBreak: .rule
        case .tableRow, .tableHeaderRow: .tableRow
        default: .paragraph
        }
        let marker = listMarker(components, markedItems: &markedItems)
        let listDepth = components.count { component in
            switch component.kind {
            case .orderedList, .unorderedList: true
            default: false
            }
        }
        let quoteDepth = components.count { if case .blockQuote = $0.kind { true } else { false } }
        return Block(
            id: key?.identity ?? -1,
            kind: kind,
            text: text,
            listMarker: marker,
            listDepth: listDepth,
            quoteDepth: quoteDepth
        )
    }

    /// For the first block of the list item nearest the block, which `markedItems` remembers.
    private static func listMarker(_ components: [PresentationIntent.IntentType], markedItems: inout Set<Int>) -> String? {
        guard let index = components.firstIndex(where: { if case .listItem = $0.kind { true } else { false } }),
              case let .listItem(ordinal) = components[index].kind,
              markedItems.insert(components[index].identity).inserted
        else { return nil }
        let isOrdered = components.dropFirst(index + 1).first.map { if case .orderedList = $0.kind { true } else { false } } ?? false
        return isOrdered ? "\(ordinal)." : "•"
    }
}
