import Foundation
import Testing

struct DistinctFolderNamesTests {
    private func names(_ paths: String...) -> [String] {
        DistinctFolderNames.make(for: paths.map { URL(filePath: $0, directoryHint: .isDirectory) })
    }

    @Test
    func aFolderNameNoOtherSharesStandsAlone() {
        // Act
        let names = names("/work/website", "/work/api")

        // Assert
        #expect(names == ["website", "api"])
    }

    @Test
    func sharedNamesAddTheirParentFolders() {
        // Act
        let names = names("/work/client/app", "/work/server/app", "/work/website")

        // Assert
        #expect(names == ["client/app", "server/app", "website"])
    }

    @Test
    func addsParentFoldersUntilTheNamesDiffer() {
        // Act
        let names = names("/one/src/app", "/two/src/app")

        // Assert
        #expect(names == ["one/src/app", "two/src/app"])
    }

    @Test
    func aPathThatEndsAnotherShowsInFull() {
        // Act
        let names = names("/app", "/client/app")

        // Assert
        #expect(names == ["/app", "client/app"])
    }
}
