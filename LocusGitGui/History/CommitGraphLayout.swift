/// Where one commit sits in the graph beside the history, and the lines drawn through its row.
nonisolated struct CommitGraphRow: Equatable, Sendable {
    let lane: Int
    let color: Int
    let lines: [CommitGraphLine]

    /// How many lanes the row reaches across, which is how much room its graph needs.
    var width: Int {
        lines.reduce(lane + 1) { max($0, $1.fromLane + 1, $1.toLane + 1) }
    }
}

extension CommitGraphRow {
    /// The colour of the lines drawn together in the last lane of a row that reaches past the lanes
    /// shown, which stand for many lines rather than one.
    static let overflowColor = -1
    /// Lanes drawn beside the history. Past this, the rest are drawn together in the last one.
    static let widestDrawn = 8

    /// The row as drawn in at most `lanes` lanes. Everything past them is drawn in the last one:
    /// lines passing through out there become one line in the overflow colour, a commit out there
    /// keeps its own colour, and a line into or out of that region bends to it. A history like the
    /// Linux kernel's can run over a hundred lines side by side, which nobody can follow and which
    /// would otherwise take the whole row.
    func limited(toLanes lanes: Int) -> CommitGraphRow {
        guard lanes > 0, width > lanes else { return self }
        let last = lanes - 1
        var limited: [CommitGraphLine] = []
        for line in lines {
            let isOverflow = line.fromLane >= last && line.toLane >= last
            let drawn = CommitGraphLine(
                fromLane: min(line.fromLane, last),
                toLane: min(line.toLane, last),
                span: line.span,
                color: isOverflow ? Self.overflowColor : line.color
            )
            if !limited.contains(drawn) {
                limited.append(drawn)
            }
        }
        return CommitGraphRow(lane: min(lane, last), color: color, lines: limited)
    }
}

/// One line through a row of the graph.
nonisolated struct CommitGraphLine: Equatable, Sendable {
    enum Span: Sendable {
        /// From the top of the row to the commit, from a child above.
        case incoming
        /// From the commit to the bottom of the row, toward a parent below.
        case outgoing
        /// Top to bottom, for a line of history that has no commit in this row.
        case passing
    }

    let fromLane: Int
    let toLane: Int
    let span: Span
    /// An index into the graph's palette, which the view wraps around.
    let color: Int
}

/// Lays out the graph one commit at a time, newest first, so each page of history carries on from
/// where the last one left off. It needs each commit after all its children, which `--topo-order`
/// guarantees.
///
/// A lane waits for the commit it expects next. Lanes never shift sideways, so a line that isn't
/// meeting anything runs straight down; a lane that empties is reused by the next new line.
nonisolated struct CommitGraphLayout {
    private var lanes: [String?] = []
    private var colors: [Int] = []
    private var nextColor = 0

    mutating func add(_ hash: String, parents: [String]) -> CommitGraphRow {
        let waiting = lanes.indices.filter { lanes[$0] == hash }
        let lane = waiting.first ?? allocateLane()
        let color = colors[lane]

        var lines: [CommitGraphLine] = []
        for (index, expected) in lanes.enumerated() {
            guard let expected else { continue }
            lines.append(expected == hash
                ? .init(fromLane: index, toLane: lane, span: .incoming, color: colors[index])
                : .init(fromLane: index, toLane: index, span: .passing, color: colors[index]))
        }
        for index in waiting {
            lanes[index] = nil
        }

        if let first = parents.first {
            // A branch that started from a commit another lane is already waiting for joins that
            // lane at once, rather than running beside it all the way down.
            if let existing = lanes.firstIndex(of: first), existing < lane {
                lines.append(.init(fromLane: lane, toLane: existing, span: .outgoing, color: color))
            } else {
                lanes[lane] = first
                lines.append(.init(fromLane: lane, toLane: lane, span: .outgoing, color: color))
            }
        }
        for parent in parents.dropFirst() {
            let target = lanes.firstIndex(of: parent) ?? {
                let new = allocateLane()
                lanes[new] = parent
                return new
            }()
            lines.append(.init(fromLane: lane, toLane: target, span: .outgoing, color: colors[target]))
        }

        while lanes.last == .some(nil) {
            lanes.removeLast()
            colors.removeLast()
        }
        return CommitGraphRow(lane: lane, color: color, lines: lines)
    }

    /// The leftmost empty lane, or a new one at the right, in a colour of its own.
    private mutating func allocateLane() -> Int {
        let lane = lanes.firstIndex(of: nil) ?? {
            lanes.append(nil)
            colors.append(0)
            return lanes.count - 1
        }()
        colors[lane] = nextColor
        nextColor += 1
        return lane
    }
}
