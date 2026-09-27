import Foundation

/// How one command's questions reach the app: the helper Git and SSH run to ask, the socket the
/// helper asks over, and the token that tells the app which command is asking.
nonisolated struct AskpassChannel: Equatable, Sendable {
    let helper: URL
    let socket: URL
    let token: String
}
