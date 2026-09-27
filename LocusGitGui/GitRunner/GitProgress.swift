import Foundation

/// How far a fetch, pull, push or clone has got, from the progress Git writes to standard error
/// with `--progress`, such as `Receiving objects:  45% (450/1000), 1.20 MiB | 2.00 MiB/s`. The
/// phase names are Git's, in English, which `GitEnvironment` makes sure of.
nonisolated struct GitProgress: Equatable, Sendable {
    /// Such as “Receiving objects”, without the `remote:` a phase on the server has in front.
    let phase: String
    let completed: Int
    /// Nil for a phase that only counts, such as the server enumerating objects.
    let total: Int?

    var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(Double(completed) / Double(total), 1)
    }

    /// As a progress bar's caption, such as “Receiving objects 45%”.
    var summary: String {
        guard let fraction else {
            return "\(phase) \(completed.formatted())"
        }
        return "\(phase) \(Int(fraction * 100))%"
    }

    /// Git writes a line for every object in some phases, far more often than a bar can show.
    func looksTheSame(as other: GitProgress?) -> Bool {
        guard let other, other.phase == phase else { return false }
        guard let fraction, let otherFraction = other.fraction else { return other.completed == completed }
        return Int(fraction * 100) == Int(otherFraction * 100)
    }

    /// Reads progress as it arrives, which can split a line anywhere.
    struct Reader: Sendable {
        private var partial = Data()

        /// The latest progress in `data`, or nil when it holds none.
        mutating func consume(_ data: Data) -> GitProgress? {
            partial.append(data)
            var latest: GitProgress?
            while let end = partial.firstIndex(where: { $0 == UInt8(ascii: "\r") || $0 == UInt8(ascii: "\n") }) {
                if let line = String(bytes: partial[partial.startIndex ..< end], encoding: .utf8), let progress = GitProgress(line: line) {
                    latest = progress
                }
                partial.removeSubrange(partial.startIndex ... end)
            }
            return latest
        }
    }

    init(phase: String, completed: Int, total: Int?) {
        self.phase = phase
        self.completed = completed
        self.total = total
    }

    init?(line: String) {
        let line = line.hasPrefix("remote: ") ? String(line.dropFirst("remote: ".count)) : line
        if let match = line.firstMatch(of: #/^(?<phase>[A-Z][a-z]+(?: [a-z]+)*): +\d+% \((?<completed>\d+)/(?<total>\d+)\)/#),
           let completed = Int(match.completed), let total = Int(match.total) {
            self.init(phase: String(match.phase), completed: completed, total: total)
        } else if let match = line.firstMatch(of: #/^(?<phase>[A-Z][a-z]+(?: [a-z]+)*): (?<completed>\d+)(?:,|$)/#),
                  let completed = Int(match.completed) {
            self.init(phase: String(match.phase), completed: completed, total: nil)
        } else {
            return nil
        }
    }
}
