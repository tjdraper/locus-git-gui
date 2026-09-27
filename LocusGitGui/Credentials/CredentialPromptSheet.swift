import SwiftUI

/// What Git or SSH asked, as a sheet: a username, a password or token, a key's passphrase, whether to
/// trust a server met for the first time, or a question the app doesn't know, in its own words.
struct CredentialPromptSheet: View {
    let prompt: CredentialPrompt
    /// What the command asking is doing, such as “Fetching from “origin””.
    let activity: String
    /// The same question came again, which for a passphrase means the last one was wrong.
    let isRepeat: Bool
    /// Nil when the user cancelled.
    let finish: (String?) -> Void

    @State private var answer = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                    Text(activity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if isRepeat {
                        Label("That didn’t work. Try again.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if case let .unknownHost(_, _, fingerprint?) = prompt {
                Text(fingerprint)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    }
            }
            field
            HStack {
                Spacer()
                Button("Cancel") { finish(nil) }
                    .keyboardShortcut(.cancelAction)
                if let confirmTitle {
                    Button(confirmTitle) { finish(confirmedAnswer) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(needsAnswer && answer.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            // SwiftUI ignores a focus change made in the same pass the view appears in.
            DispatchQueue.main.async {
                isFieldFocused = true
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        switch prompt {
        case .username:
            TextField("Username", text: $answer)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
                .focused($isFieldFocused)
        case .password:
            SecureField("Password or Token", text: $answer)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .focused($isFieldFocused)
        case .passphrase:
            SecureField("Passphrase", text: $answer)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
        case .other:
            SecureField("Answer", text: $answer)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
        case .unknownHost, .confirmation, .notice:
            EmptyView()
        }
    }

    private var title: String {
        switch prompt {
        case let .username(server), let .password(_, server): "Sign in to \(server)"
        case let .passphrase(keyPath) where CredentialPrompt.isCutShort(keyPath): "Unlock an SSH key"
        case let .passphrase(keyPath): "Unlock the SSH key “\((keyPath as NSString).lastPathComponent)”"
        case let .unknownHost(host, _, _): "Connect to \(host)?"
        case .confirmation: "SSH is asking for confirmation"
        case .notice: "SSH is waiting"
        case .other: "Git is asking for an answer"
        }
    }

    private var message: String {
        switch prompt {
        case let .username(server):
            "Enter your username for \(server)."
        case let .password(account?, server):
            "Enter the password or access token for “\(account)” on \(server)."
        case let .password(nil, server):
            "Enter the password or access token for \(server)."
        case let .passphrase(keyPath) where CredentialPrompt.isCutShort(keyPath):
            "Enter the passphrase for the key at \((keyPath as NSString).abbreviatingWithTildeInPath)…"
        case let .passphrase(keyPath):
            "Enter the passphrase for \((keyPath as NSString).abbreviatingWithTildeInPath)."
        case let .unknownHost(host, keyType, _):
            """
            This Mac hasn’t connected to \(host) before. Check that its \(keyType.map { "\($0) " } ?? "")key \
            fingerprint below matches the one its owner publishes before connecting. SSH remembers the \
            server once you connect.
            """
        case let .confirmation(text), let .notice(text), let .other(text):
            text
        }
    }

    private var symbol: String {
        switch prompt {
        case .username, .password: "person.badge.key"
        case .passphrase: "key"
        case .unknownHost: "server.rack"
        case .confirmation, .other: "questionmark.circle"
        case .notice: "hand.tap"
        }
    }

    /// A notice has nothing to answer, only Cancel.
    private var confirmTitle: String? {
        switch prompt {
        case .unknownHost: "Connect"
        case .confirmation: "Allow"
        case .notice: nil
        case .username, .password, .passphrase, .other: "Continue"
        }
    }

    private var needsAnswer: Bool {
        switch prompt {
        case .username, .password, .passphrase: true
        case .unknownHost, .confirmation, .notice, .other: false
        }
    }

    private var confirmedAnswer: String {
        switch prompt {
        case .unknownHost, .confirmation: CredentialPrompt.yes
        case .username, .password, .passphrase, .notice, .other: answer
        }
    }
}
