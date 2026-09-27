import Foundation
import os

/// Passes the questions Git and SSH ask, such as for a password or a passphrase, to the command
/// that's waiting on the answer. Each command that may be asked opens a channel for the time it
/// runs, and a question for a command that's finished is declined. One for the app.
final class AskpassServer {
    /// An answer, or nil when the user declined.
    typealias Answering = (CredentialPrompt) async -> String?

    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "Askpass")

    private let helper = Bundle.main.bundleURL.appending(path: "Contents/Helpers/LocusGitGuiAskpass")
    /// The user's own temporary folder, which only they can read. A socket path has to fit in 104
    /// bytes, which a folder in Application Support can't promise.
    private let socket = FileManager.default.temporaryDirectory.appending(path: "com.buzzingpixel.LocusGitGui.askpass.\(getpid())")
    private let queue = DispatchQueue(label: "com.buzzingpixel.LocusGitGui.askpass")
    private var listener: (any DispatchSourceRead)?
    private var answering: [String: Answering] = [:]
    private var waiting: [String: [UUID: Task<String?, Never>]] = [:]

    /// Nil when there's no way to ask, and the command then runs without one, as a command the user
    /// didn't start does.
    func open(_ answer: @escaping Answering) -> AskpassChannel? {
        guard startIfNeeded() else { return nil }
        let token = UUID().uuidString
        answering[token] = answer
        return AskpassChannel(helper: helper, socket: socket, token: token)
    }

    /// Once the command has finished. A question it left waiting is declined.
    func close(_ channel: AskpassChannel?) {
        guard let channel else { return }
        answering[channel.token] = nil
        for task in (waiting.removeValue(forKey: channel.token) ?? [:]).values {
            task.cancel()
        }
    }

    /// As the app quits, so the socket's file doesn't outlive it.
    func stop() {
        listener?.cancel()
        listener = nil
        unlink(socket.path)
    }

    private func startIfNeeded() -> Bool {
        guard listener == nil else { return true }
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            Self.log.error("The askpass helper is missing from the app")
            return false
        }
        do {
            let descriptor = try AskpassSocket.listen(at: socket.path)
            listener = AskpassSocket.accept(on: descriptor, queue: queue) { [weak self] connection, request in
                Task { @MainActor in
                    guard let self else {
                        AskpassSocket.decline(connection)
                        return
                    }
                    self.ask(request, on: connection)
                }
            }
            return true
        } catch {
            Self.log.error("The askpass socket couldn't start: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func ask(_ request: AskpassSocket.Request, on connection: Int32) {
        guard let answer = answering[request.token] else {
            AskpassSocket.decline(connection)
            return
        }
        let prompt = CredentialPrompt.parse(request.prompt, hint: request.hint)
        Self.log.info("Asked \(String(describing: prompt.kind), privacy: .public)")
        let id = UUID()
        let task = Task { await answer(prompt) }
        waiting[request.token, default: [:]][id] = task
        let held = AskpassSocket.hold(connection, queue: queue) { task.cancel() }
        Task { [queue] in
            let reply = await task.value
            waiting[request.token]?[id] = nil
            AskpassSocket.answer(reply, on: connection, held: held, queue: queue)
        }
    }
}

extension CredentialPrompt {
    /// For the log, which never gets the question itself: it can name hosts, accounts and paths.
    fileprivate var kind: String {
        switch self {
        case .username: "username"
        case .password: "password"
        case .passphrase: "passphrase"
        case .unknownHost: "unknown host"
        case .confirmation: "confirmation"
        case .notice: "notice"
        case .other: "other"
        }
    }
}
