import Darwin
import Foundation

/// The Unix socket the askpass helper asks the app over. A question arrives as one line of JSON, and
/// the answer goes back as JSON before the connection closes. The helper keeps its end open while it
/// waits, so the connection closing early means Git or SSH gave up on the question.
nonisolated enum AskpassSocket {
    struct Request: Decodable, Sendable {
        let token: String
        let prompt: String
        let hint: String?
    }

    private struct Reply: Encodable {
        let answer: String?
    }

    enum Failure: Error {
        case pathTooLong
        case couldNotListen(Int32)
    }

    /// A request longer than any question Git or SSH asks isn't one.
    private static let requestLimit = 64 * 1024

    /// Only the user can connect: the socket is in their own temporary folder and readable by them
    /// alone.
    static func listen(at path: String) throws -> Int32 {
        unlink(path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure.couldNotListen(errno) }
        var address = try address(for: path)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(descriptor, 16) == 0 else {
            let error = errno
            close(descriptor)
            throw Failure.couldNotListen(error)
        }
        return descriptor
    }

    /// Calls `onRequest` away from the main actor for each question that arrives.
    static func accept(
        on listener: Int32,
        queue: DispatchQueue,
        onRequest: @escaping @Sendable (Int32, Request) -> Void
    ) -> any DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
        source.setEventHandler {
            let connection = Darwin.accept(listener, nil, nil)
            guard connection >= 0 else { return }
            var noSignal: Int32 = 1
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            // A helper that connects and then says nothing mustn't hold up the queue.
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            guard let line = readLine(from: connection), let request = try? JSONDecoder().decode(Request.self, from: line) else {
                close(connection)
                return
            }
            onRequest(connection, request)
        }
        source.setCancelHandler {
            close(listener)
        }
        source.resume()
        return source
    }

    /// Holds the connection while the question waits for the user, and calls `onHangUp` if the
    /// helper goes away first, such as when Git is stopped. The returned source owns the connection
    /// and closes it once cancelled, so nothing writes to a descriptor that's been closed and reused.
    static func hold(_ connection: Int32, queue: DispatchQueue, onHangUp: @escaping @Sendable () -> Void) -> any DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: connection, queue: queue)
        source.setEventHandler { [weak source] in
            var byte: UInt8 = 0
            if recv(connection, &byte, 1, MSG_PEEK | MSG_DONTWAIT) == 0 {
                source?.cancel()
                onHangUp()
            }
        }
        source.setCancelHandler {
            close(connection)
        }
        source.resume()
        return source
    }

    /// Answers a held question, unless the helper has already gone. Nil tells the helper the
    /// question was declined.
    static func answer(_ answer: String?, on connection: Int32, held source: any DispatchSourceRead, queue: DispatchQueue) {
        queue.async {
            if !source.isCancelled {
                send(answer, on: connection)
            }
            source.cancel()
        }
    }

    /// For a question nothing is waiting to answer.
    static func decline(_ connection: Int32) {
        send(nil, on: connection)
        close(connection)
    }

    private static func send(_ answer: String?, on connection: Int32) {
        guard let data = try? JSONEncoder().encode(Reply(answer: answer)) else { return }
        _ = data.withUnsafeBytes { buffer in
            Darwin.send(connection, buffer.baseAddress, buffer.count, 0)
        }
    }

    private static func readLine(from connection: Int32) -> Data? {
        var line = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while line.count < requestLimit {
            let count = recv(connection, &buffer, buffer.count, 0)
            guard count > 0 else { return nil }
            let chunk = buffer.prefix(count)
            if let newline = chunk.firstIndex(of: UInt8(ascii: "\n")) {
                line.append(contentsOf: chunk[..<newline])
                return line
            }
            line.append(contentsOf: chunk)
        }
        return nil
    }

    private static func address(for path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw Failure.pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        return address
    }
}
