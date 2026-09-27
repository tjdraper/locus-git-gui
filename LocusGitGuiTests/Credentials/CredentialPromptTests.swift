import Testing

/// The questions as Git 2.42 and OpenSSH 10 asked them through the helper.
struct CredentialPromptTests {
    @Test
    func httpsUsername() {
        // Arrange
        let text = "Username for 'https://github.com': "

        // Act
        let prompt = CredentialPrompt.parse(text, hint: nil)

        // Assert
        #expect(prompt == .username(server: "github.com"))
    }

    @Test
    func httpsPasswordNamesTheAccount() {
        // Arrange
        let text = "Password for 'http://git@127.0.0.1:8765': "

        // Act
        let prompt = CredentialPrompt.parse(text, hint: nil)

        // Assert
        #expect(prompt == .password(account: "git", server: "127.0.0.1:8765"))
    }

    @Test
    func sshKeyPassphrase() {
        // Arrange
        let text = "Enter passphrase for key '/Users/someone/.ssh/id_ed25519': "

        // Act
        let prompt = CredentialPrompt.parse(text, hint: nil)

        // Assert
        #expect(prompt == .passphrase(keyPath: "/Users/someone/.ssh/id_ed25519"))
    }

    @Test
    func unknownHostWithItsFingerprint() {
        // Arrange
        let text = """
        The authenticity of host '[127.0.0.1]:2222 ([127.0.0.1]:2222)' can't be established.
        ED25519 key fingerprint is: SHA256:BQ+uF+t1B6TYGU/bACN4llvA6+mJzvGZdc5VUjkVJj0
        This key is not known by any other names.
        Are you sure you want to continue connecting (yes/no/[fingerprint])?
        """

        // Act
        let prompt = CredentialPrompt.parse(text, hint: nil)

        // Assert
        #expect(prompt == .unknownHost(
            host: "[127.0.0.1]:2222",
            keyType: "ED25519",
            fingerprint: "SHA256:BQ+uF+t1B6TYGU/bACN4llvA6+mJzvGZdc5VUjkVJj0"
        ))
    }

    @Test
    func olderSSHEndsTheFingerprintWithAFullStop() {
        // Arrange
        let text = """
        The authenticity of host 'github.com (140.82.121.4)' can't be established.
        ECDSA key fingerprint is SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM.
        Are you sure you want to continue connecting (yes/no/[fingerprint])?
        """

        // Act
        let prompt = CredentialPrompt.parse(text, hint: nil)

        // Assert
        #expect(prompt == .unknownHost(
            host: "github.com",
            keyType: "ECDSA",
            fingerprint: "SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM"
        ))
    }

    @Test
    func sshAccountPassword() {
        // Arrange
        let text = "someone@example.com's password: "

        // Act
        let prompt = CredentialPrompt.parse(text, hint: nil)

        // Assert
        #expect(prompt == .password(account: "someone", server: "example.com"))
    }

    @Test
    func keyboardInteractivePassword() {
        // Arrange
        let text = "(someone@example.com) Password: "

        // Act
        let prompt = CredentialPrompt.parse(text, hint: nil)

        // Assert
        #expect(prompt == .password(account: "someone", server: "example.com"))
    }

    @Test
    func sshNoticeEndsBySelf() {
        // Arrange
        let text = "Confirm user presence for key ED25519-SK SHA256:abc"

        // Act
        let prompt = CredentialPrompt.parse(text, hint: "none")

        // Assert
        #expect(prompt == .notice(text))
    }

    @Test
    func sshConfirmation() {
        // Arrange
        let text = "Allow use of key /Users/someone/.ssh/id_ed25519?\nKey fingerprint SHA256:abc."

        // Act
        let prompt = CredentialPrompt.parse(text, hint: "confirm")

        // Assert
        #expect(prompt == .confirmation(text))
    }

    @Test
    func anythingElseIsAskedInItsOwnWords() {
        // Arrange
        let text = "Enter PIN for ED25519-SK key /Users/someone/.ssh/id_ed25519_sk: "

        // Act
        let prompt = CredentialPrompt.parse(text, hint: nil)

        // Assert
        #expect(prompt == .other("Enter PIN for ED25519-SK key /Users/someone/.ssh/id_ed25519_sk:"))
    }

    @Test
    func aKeyPathSSHCutShortIsKnownToBe() {
        // Arrange
        // A path of 100 bytes, as SSH leaves a longer one.
        let text = "Enter passphrase for key '/Users/someone/\(String(repeating: "k", count: 85))': "

        // Act
        let prompt = CredentialPrompt.parse(text, hint: nil)

        // Assert
        guard case let .passphrase(keyPath) = prompt else {
            Issue.record("Not a passphrase: \(prompt)")
            return
        }
        #expect(CredentialPrompt.isCutShort(keyPath))
        #expect(!CredentialPrompt.isCutShort("/Users/someone/.ssh/id_ed25519"))
    }
}
