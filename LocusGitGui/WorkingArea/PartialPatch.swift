import Foundation

/// A patch of some of the changed lines of one hunk, for `git apply` to stage, unstage or discard
/// just those lines. See https://git-scm.com/docs/git-apply
///
/// Staging applies the unstaged changes to the index. A removed line that isn't picked stays in the
/// index, so it becomes an unchanged line, and an added line that isn't picked is left out.
///
/// Unstaging and discarding apply the staged or unstaged changes in reverse, to the index or the
/// working tree. There it's the other way around: an added line that isn't picked stays, so it
/// becomes an unchanged line, and a removed line that isn't picked is left out.
nonisolated enum PartialPatch {
    enum Direction: Sendable {
        /// Applied as it is, as staging does.
        case forward
        /// Applied in reverse, as unstaging and discarding do.
        case reverse
    }

    /// Nil when none of `lines` is a changed line. `lines` are indices into the hunk's lines.
    static func make(
        from patch: RawFilePatch,
        hunk index: Int,
        lines picked: Set<Int>,
        path: String,
        direction: Direction
    ) -> Data? {
        guard patch.hunks.indices.contains(index) else { return nil }
        let hunk = patch.hunks[index]
        var body: [RawFilePatch.Line] = []
        var hasChange = false
        for (lineIndex, line) in hunk.lines.enumerated() {
            let isPicked = picked.contains(lineIndex)
            switch (line.kind, direction) {
            case (.context, _):
                body.append(line)
            case (.removed, _) where isPicked, (.added, _) where isPicked:
                body.append(line)
                hasChange = true
            case (.removed, .forward), (.added, .reverse):
                body.append(RawFilePatch.Line(kind: .context, text: line.text, hasNoNewlineAtEnd: line.hasNoNewlineAtEnd))
            case (.added, .forward), (.removed, .reverse):
                continue
            }
        }
        guard hasChange else { return nil }

        // Staging part of a new file adds it to the index with only those lines. Anything else is
        // written as a change to the file where it is, which also keeps a staged rename or a new
        // file in place when some of its lines are unstaged.
        let isNewFile = direction == .forward && patch.isNewFile
        let oldCount = body.count { $0.kind != .added }
        let newCount = body.count { $0.kind != .removed }
        // The side Git matches the patch against, the old side going forward and the new one in
        // reverse, is the same lines as in Git's own hunk, so its first line is too. The patch holds
        // only this hunk, so the other side starts at the same line.
        let firstLine = direction == .forward
            ? Self.firstLine(start: hunk.oldStart, count: hunk.lines.count { $0.kind != .added })
            : Self.firstLine(start: hunk.newStart, count: hunk.lines.count { $0.kind != .removed })
        var text = Data()
        func line(_ string: String) {
            text.append(Data(string.utf8))
            text.append(UInt8(ascii: "\n"))
        }
        line("diff --git \(GitPatchPath.quoted("a/" + path)) \(GitPatchPath.quoted("b/" + path))")
        if isNewFile, let mode = patch.header.first(where: { $0.starts(with: Data("new file mode ".utf8)) }) {
            text.append(mode)
            text.append(UInt8(ascii: "\n"))
        }
        line("--- " + (isNewFile ? "/dev/null" : GitPatchPath.quoted("a/" + path)))
        line("+++ " + GitPatchPath.quoted("b/" + path))
        line("@@ -\(Self.range(firstLine: firstLine, count: oldCount)) +\(Self.range(firstLine: firstLine, count: newCount)) @@")
        for bodyLine in body {
            text.append(prefix(of: bodyLine.kind))
            text.append(bodyLine.text)
            text.append(UInt8(ascii: "\n"))
            if bodyLine.hasNoNewlineAtEnd {
                line("\\ No newline at end of file")
            }
        }
        return text
    }

    /// Git writes an empty side's start as the line before it, which is 0 at the top of the file.
    private static func firstLine(start: Int, count: Int) -> Int {
        count == 0 ? start + 1 : start
    }

    private static func range(firstLine: Int, count: Int) -> String {
        "\(count == 0 ? firstLine - 1 : firstLine),\(count)"
    }

    private static func prefix(of kind: DiffLine.Kind) -> UInt8 {
        switch kind {
        case .context: UInt8(ascii: " ")
        case .added: UInt8(ascii: "+")
        case .removed: UInt8(ascii: "-")
        }
    }
}

/// A path as a patch names it, quoted the way Git quotes one that has characters a patch can't
/// hold as they are.
nonisolated enum GitPatchPath {
    static func quoted(_ path: String) -> String {
        let needsQuotes = path.unicodeScalars.contains { $0 == "\"" || $0 == "\\" || $0.value < 0x20 || $0.value == 0x7F }
        guard needsQuotes else { return path }
        var quoted = "\""
        for scalar in path.unicodeScalars {
            switch scalar {
            case "\"": quoted += "\\\""
            case "\\": quoted += "\\\\"
            case "\t": quoted += "\\t"
            case "\n": quoted += "\\n"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                quoted += "\\" + String(scalar.value, radix: 8).leftPadded(to: 3)
            default:
                quoted.unicodeScalars.append(scalar)
            }
        }
        return quoted + "\""
    }
}

nonisolated private extension String {
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(length - count, 0)) + self
    }
}
