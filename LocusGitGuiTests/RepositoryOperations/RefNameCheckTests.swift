import Testing

struct RefNameCheckTests {
    @Test(arguments: ["feature", "feature/login", "fix-12", "v1.0"])
    func acceptsOrdinaryNames(name: String) {
        // Act
        let problem = RefNameCheck.problem(with: name, kind: "branch", taken: [])

        // Assert
        #expect(problem == nil)
    }

    @Test(arguments: ["two words", "a..b", "a:b", "-flag", "ends/", "name.lock", "a@{b", "a//b", "@"])
    func refusesWhatGitRefuses(name: String) {
        // Act
        let problem = RefNameCheck.problem(with: name, kind: "branch", taken: [])

        // Assert
        #expect(problem != nil)
    }

    @Test
    func refusesATakenName() {
        // Act
        let problem = RefNameCheck.problem(with: "main", kind: "branch", taken: ["main"])

        // Assert
        #expect(problem == "There’s already a branch named “main”.")
    }
}
