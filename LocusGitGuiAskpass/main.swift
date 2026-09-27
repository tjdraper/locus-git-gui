import Foundation

// Git runs this as `GIT_ASKPASS` and SSH as `SSH_ASKPASS` when they need a password, a passphrase or
// an answer to a question, with the question as the only argument. It asks Locus Git Gui over the
// socket the app named in the environment, and prints the answer for Git or SSH to read. Exiting
// without printing anything tells them the user declined.

struct Request: Encodable {
    let token: String
    let prompt: String
    /// SSH's `SSH_ASKPASS_PROMPT`: `confirm` for a yes or no question, `none` for a notice such as
    /// touching a security key, which SSH ends itself once it's done.
    let hint: String?
}

struct Reply: Decodable {
    let answer: String?
}

let environment = ProcessInfo.processInfo.environment
guard let socketPath = environment["LOCUS_ASKPASS_SOCKET"], let token = environment["LOCUS_ASKPASS_TOKEN"] else {
    FileHandle.standardError.write(Data("Locus Git Gui isn’t running this command, so it can’t ask for the answer.\n".utf8))
    exit(1)
}

func connect(to path: String) -> Int32? {
    let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard socket >= 0 else { return nil }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.copyBytes(from: pathBytes)
    }
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else {
        close(socket)
        return nil
    }
    return socket
}

guard let socket = connect(to: socketPath),
      let request = try? JSONEncoder().encode(Request(
          token: token,
          prompt: CommandLine.arguments.dropFirst().first ?? "",
          hint: environment["SSH_ASKPASS_PROMPT"]
      ))
else {
    exit(1)
}

let handle = FileHandle(fileDescriptor: socket, closeOnDealloc: true)
do {
    // One line, which JSON's escaping of line breaks keeps it to. The connection stays open both
    // ways while the app asks, so the app can tell when Git or SSH stops waiting and ends this.
    try handle.write(contentsOf: request + Data("\n".utf8))
} catch {
    exit(1)
}

guard let data = try? handle.readToEnd(),
      let reply = try? JSONDecoder().decode(Reply.self, from: data),
      let answer = reply.answer
else {
    exit(1)
}
FileHandle.standardOutput.write(Data((answer + "\n").utf8))
