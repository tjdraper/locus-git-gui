import Testing

struct TerminalOutputTests {
    @Test
    func progressShowsOnlyWhereItGotTo() {
        // Arrange
        let text = "Cloning into 'dst'...\n"
            + "remote: Counting objects:   0% (1/302)        \rremote: Counting objects: 100% (302/302), done.        \n"
            + "Done"

        // Act
        let rendered = TerminalOutput.rendered(text)

        // Assert
        #expect(rendered == "Cloning into 'dst'...\nremote: Counting objects: 100% (302/302), done.\nDone")
    }

    @Test
    func textWithoutProgressIsUnchanged() {
        // Arrange
        let text = "error: failed to push some refs\n\nhint: Updates were rejected"

        // Act
        let rendered = TerminalOutput.rendered(text)

        // Assert
        #expect(rendered == text)
    }
}
