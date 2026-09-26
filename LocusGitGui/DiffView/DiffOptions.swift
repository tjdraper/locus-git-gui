import Foundation

/// How Git writes a repository's diffs, remembered with the repository's view state.
nonisolated struct DiffOptions: Codable, Equatable, Sendable {
    /// The steps More and Fewer Context Lines move through. Git's own default is 3.
    static let contextSteps = [0, 1, 3, 5, 10, 25, 100]

    var ignoresWhitespace = false
    var contextLines = 3

    var arguments: [String] {
        (ignoresWhitespace ? ["--ignore-all-space"] : []) + ["--unified=\(contextLines)"]
    }

    var moreContext: Int? {
        Self.contextSteps.first { $0 > contextLines }
    }

    var lessContext: Int? {
        Self.contextSteps.last { $0 < contextLines }
    }
}

nonisolated extension DiffOptions {
    /// Each field is optional when decoding, so options saved before a field existed still read.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ignoresWhitespace = try container.decodeIfPresent(Bool.self, forKey: .ignoresWhitespace) ?? false
        contextLines = try container.decodeIfPresent(Int.self, forKey: .contextLines) ?? 3
    }
}
