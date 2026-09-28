import AppKit
import Testing

struct DiffPreferencesTests {
    private let suiteName = "DiffPreferencesTests-\(UUID().uuidString)"

    private func makePreferences() throws -> DiffPreferences {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return DiffPreferences(defaults: defaults)
    }

    @Test
    func startsAsTheDiffAlwaysWas() throws {
        // Arrange
        let preferences = try makePreferences()

        // Assert
        #expect(preferences.layout == .automatic)
        #expect(preferences.fontFamily == nil)
        #expect(preferences.fontSize == DiffPreferences.defaultFontSize)
        #expect(preferences.defaultOptions == DiffOptions())
    }

    @Test
    func keepsWhatIsChosen() throws {
        // Arrange
        let preferences = try makePreferences()

        // Act
        preferences.layout = .inline
        preferences.fontSize = 14
        preferences.defaultOptions = DiffOptions(ignoresWhitespace: true, contextLines: 10)

        // Assert
        #expect(preferences.layout == .inline)
        #expect(preferences.fontSize == 14)
        #expect(preferences.defaultOptions == DiffOptions(ignoresWhitespace: true, contextLines: 10))
    }

    @Test
    func aContextLineCountTheMenuCantReachFallsBackToGitsDefault() throws {
        // Arrange
        let preferences = try makePreferences()

        // Act
        preferences.defaults.set(7, forKey: "DiffContextLines")

        // Assert
        #expect(preferences.defaultOptions.contextLines == DiffOptions().contextLines)
    }

    @Test
    func aFontFamilyThatIsGoneGivesWayToTheSystemFont() throws {
        // Arrange
        let preferences = try makePreferences()

        // Act
        preferences.fontFamily = "No Such Font \(UUID().uuidString)"

        // Assert
        #expect(preferences.font == NSFont.monospacedSystemFont(ofSize: DiffPreferences.defaultFontSize, weight: .regular))
    }

    @Test
    func anInstalledFontFamilyIsUsed() throws {
        // Arrange
        let preferences = try makePreferences()

        // Act
        preferences.fontFamily = "Menlo"
        preferences.fontSize = 13

        // Assert
        #expect(preferences.font.familyName == "Menlo")
        #expect(preferences.font.pointSize == 13)
    }
}
