import Testing

struct CommitMessageTests {
    @Test
    func aSubjectAloneIsTheWholeMessage() {
        // Act
        let text = CommitMessage(subject: " Fix the parser ", body: "\n  \n").text

        // Assert
        #expect(text == "Fix the parser")
    }

    @Test
    func theBodyFollowsABlankLineAndKeepsItsIndent() {
        // Act
        let text = CommitMessage(subject: "Fix the parser", body: "\n    let example = 1\n\n").text

        // Assert
        #expect(text == "Fix the parser\n\n    let example = 1")
    }

    @Test
    func aMessageIsSplitAtItsFirstLine() {
        // Act
        let message = CommitMessage(parsing: "Fix the parser\n\nIt was broken.\n\nTwice.\n")

        // Assert
        #expect(message == CommitMessage(subject: "Fix the parser", body: "It was broken.\n\nTwice."))
    }

    @Test
    func aCommitNeedsASubject() {
        // Assert
        #expect(!CommitMessage(subject: "  ", body: "Only a body").canCommit)
        #expect(CommitMessage(subject: "Subject").canCommit)
    }
}
