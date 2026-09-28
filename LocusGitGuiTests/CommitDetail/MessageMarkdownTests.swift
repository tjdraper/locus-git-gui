import Foundation
import Testing

struct MessageMarkdownTests {
    private func texts(_ markdown: MessageMarkdown) -> [String] {
        markdown.blocks.map { String($0.text.characters) }
    }

    @Test
    func joinsLinesWrappedWithinAParagraph() {
        // Act
        let markdown = MessageMarkdown("Wrapped at seventy-two characters, so the\nsentence runs on.\n\nA second paragraph.")

        // Assert
        #expect(texts(markdown) == ["Wrapped at seventy-two characters, so the sentence runs on.", "A second paragraph."])
        #expect(markdown.blocks.map(\.kind) == [.paragraph, .paragraph])
    }

    @Test
    func marksTheFirstBlockOfEachListItemAndNestsDeeperLists() {
        // Act
        let markdown = MessageMarkdown("- One\n- Two\n  - Nested\n\n1. First\n2. Second")

        // Assert
        #expect(texts(markdown) == ["One", "Two", "Nested", "First", "Second"])
        #expect(markdown.blocks.map(\.listMarker) == ["•", "•", "•", "1.", "2."])
        #expect(markdown.blocks.map(\.listDepth) == [1, 1, 2, 1, 1])
    }

    @Test
    func readsHeadingsQuotesAndCode() {
        // Act
        let markdown = MessageMarkdown("## Why\n\n> Quoted\n\n```swift\nlet x = 1\n```")

        // Assert
        #expect(markdown.blocks.map(\.kind) == [.heading(level: 2), .paragraph, .code])
        #expect(texts(markdown) == ["Why", "Quoted", "let x = 1"])
        #expect(markdown.blocks.map(\.quoteDepth) == [0, 1, 0])
    }

    @Test
    func keepsWebLinksAndDropsOthers() {
        // Act
        let markdown = MessageMarkdown("[Docs](https://example.com) and [a file](file:///etc/hosts)")

        // Assert
        let links = markdown.blocks[0].text.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://example.com")])
        #expect(texts(markdown) == ["Docs and a file"])
    }

    @Test
    func leavesIssueReferencesAndIdentifiersAsText() {
        // Act
        let markdown = MessageMarkdown("Fixes #123 in some_function_name.")

        // Assert
        #expect(texts(markdown) == ["Fixes #123 in some_function_name."])
        #expect(markdown.blocks[0].text.runs.allSatisfy { $0.link == nil && $0.inlinePresentationIntent == nil })
    }

    @Test
    func runsATableRowsCellsTogether() {
        // Act
        let markdown = MessageMarkdown("| Name | Size |\n|---|---|\n| a | 1 |")

        // Assert
        #expect(markdown.blocks.map(\.kind) == [.tableRow, .tableRow])
        #expect(texts(markdown) == ["Name │ Size", "a │ 1"])
    }
}
