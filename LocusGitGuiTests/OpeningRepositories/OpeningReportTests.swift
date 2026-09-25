import Foundation
import Testing

struct OpeningReportTests {
    private let home = URL(filePath: NSHomeDirectory())

    @Test
    func nothingToReportMakesNoReport() {
        // Arrange
        let folders: [OpeningReport.Folder] = []

        // Act
        let report = OpeningReport(folders: folders)

        // Assert
        #expect(report == nil)
    }

    @Test
    func oneFolderIsNamedWithItsPath() throws {
        // Arrange
        let folder = OpeningReport.Folder(url: home.appending(path: "Projects/Notes"), problem: .notRepository)

        // Act
        let report = try #require(OpeningReport(folders: [folder]))

        // Assert
        #expect(report.messageText == "“Notes” isn't a Git repository")
        #expect(report.informativeText == "~/Projects/Notes")
        #expect(!report.offersPrivacySettings)
    }

    @Test
    func severalFoldersShareOneReportAndOfferPrivacySettingsWhenNeeded() throws {
        // Arrange
        let folders = [
            OpeningReport.Folder(url: home.appending(path: "Notes"), problem: .notRepository),
            OpeningReport.Folder(url: home.appending(path: "Server.git"), problem: .bare),
            OpeningReport.Folder(url: home.appending(path: "Documents/Site"), problem: .accessDenied),
        ]

        // Act
        let report = try #require(OpeningReport(folders: folders))

        // Assert
        #expect(report.messageText == "3 folders couldn't be opened")
        #expect(report.informativeText.hasPrefix("""
        “Notes” isn't a Git repository.
        “Server.git” is a bare repository, with no working files to show.
        Locus Git Gui isn't allowed to read “Site”.
        """))
        #expect(report.offersPrivacySettings)
    }
}
