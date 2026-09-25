import Testing

struct GitEnvironmentTests {
    @Test
    func readOnlyCommandsTakeNoOptionalLocks() {
        // Arrange
        let command = GitCommand.reading(["status"])

        // Act
        let variables = GitEnvironment.variables(for: command, from: [:])

        // Assert
        #expect(variables["GIT_OPTIONAL_LOCKS"] == "0")
    }

    @Test
    func changingCommandsTakeLocksAsUsual() {
        // Arrange
        let command = GitCommand.changing(["commit"])

        // Act
        let variables = GitEnvironment.variables(for: command, from: [:])

        // Assert
        #expect(variables["GIT_OPTIONAL_LOCKS"] == nil)
    }

    @Test
    func messagesAreEnglishAndTheRestOfTheLocaleIsKept() {
        // Arrange
        let base = ["LANG": "de_DE.UTF-8", "LC_CTYPE": "de_DE.UTF-8", "PATH": "/opt/homebrew/bin:/usr/bin"]

        // Act
        let variables = GitEnvironment.withEnglishMessages(base)

        // Assert
        #expect(variables["LC_MESSAGES"] == "C")
        #expect(variables["LANG"] == "de_DE.UTF-8")
        #expect(variables["LC_CTYPE"] == "de_DE.UTF-8")
        #expect(variables["PATH"] == "/opt/homebrew/bin:/usr/bin")
    }

    @Test
    func lcAllIsSpreadOverEveryCategoryButMessages() {
        // Arrange
        let base = ["LC_ALL": "de_DE.UTF-8", "LC_CTYPE": "fr_FR.UTF-8"]

        // Act
        let variables = GitEnvironment.withEnglishMessages(base)

        // Assert
        #expect(variables["LC_ALL"] == nil)
        #expect(variables["LC_CTYPE"] == "de_DE.UTF-8")
        #expect(variables["LC_COLLATE"] == "de_DE.UTF-8")
        #expect(variables["LC_MESSAGES"] == "C")
    }
}
