import Testing

struct RemoteURLTests {
    @Test(arguments: [
        "https://github.com/owner/repository.git",
        "http://127.0.0.1:8765/remote.git",
        "ssh://git@example.com:2222/srv/repository.git",
        "git://example.com/repository",
        "file:///Users/someone/repository.git",
        "git@github.com:owner/repository.git",
        "  https://github.com/owner/repository\n",
    ])
    func addressesAreOffered(_ text: String) {
        // Act
        let looksLikeRemote = RemoteURL.looksLikeRemote(text)

        // Assert
        #expect(looksLikeRemote)
    }

    @Test(arguments: [
        "",
        "repository",
        "Clone this: https://github.com/owner/repository.git",
        "https://",
        "someone@example.com",
        "/Users/someone/repository",
    ])
    func otherTextIsNot(_ text: String) {
        // Act
        let looksLikeRemote = RemoteURL.looksLikeRemote(text)

        // Assert
        #expect(!looksLikeRemote)
    }

    @Test(arguments: [
        ("https://github.com/owner/repository.git", "repository"),
        ("https://github.com/owner/repository/", "repository"),
        ("git@github.com:owner/repository.git", "repository"),
        ("git@example.com:repository.git", "repository"),
        ("/Users/someone/project/.git", "project"),
        ("ssh://git@example.com:2222/srv/tools", "tools"),
    ])
    func theFolderIsNamedAsGitWouldName(_ address: String, _ name: String) {
        // Act
        let folder = RemoteURL.repositoryName(from: address)

        // Assert
        #expect(folder == name)
    }
}
