import CoreGraphics
import Foundation
import Testing

/// Times reading and laying out diffs that are hard to show, against a repository made with
/// `Scripts/GenerateTestRepository.swift --large-changes`, whose commits are tagged `perf/…`. Skipped
/// unless `LOCUS_PERFORMANCE_REPOSITORY` names one. See Scripts/README.md.
@Suite(.enabled(if: PerformanceRepository.url != nil), .serialized)
struct DiffPerformanceTests {
    private let runner = GitRunner(executableURL: TestGit.executableURL, environment: ProcessInfo.processInfo.environment)
    private let metrics = DiffLayout.Metrics(advance: 6.6, lineHeight: 17)
    /// The detail column at its usual width, and a wide commit window.
    private let widths = [700.0, 1800.0]

    private func run(_ command: GitCommand) async throws -> ChildProcess.Result {
        try await runner.run(command, in: #require(PerformanceRepository.url))
    }

    /// As the app reads a patch: parsed as it arrives, without keeping Git's output.
    private func readPatch(
        _ command: GitCommand,
        _ limits: PatchParser.Limits
    ) async throws -> (result: ChildProcess.Result, files: [FilePatch]) {
        var parser = PatchParser(limits: limits)
        for try await event in try runner.stream(command, in: #require(PerformanceRepository.url)) {
            switch event {
            case let .standardOutput(data):
                parser.consume(data)
            case .standardError:
                break
            case let .exited(status):
                return (ChildProcess.Result(status: status, standardOutput: Data(), standardError: Data()), parser.finish())
            }
        }
        throw CancellationError()
    }

    private func hash(of tag: String) async throws -> String? {
        let result = try await run(.reading(["rev-parse", "--verify", "--quiet", "perf/\(tag)^{commit}"]))
        guard result.status == 0 else {
            write("perf/\(tag) skipped: no such tag")
            return nil
        }
        return String(bytes: result.standardOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func report(_ what: String, _ duration: Duration) {
        write("\(what): \(duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))")
    }

    private func write(_ result: String) {
        guard let repository = PerformanceRepository.url else { return }
        let file = repository.deletingLastPathComponent().appending(path: repository.lastPathComponent + "-performance.txt")
        let line = "\(Date().formatted(.iso8601)) diff: \(result)\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    /// Lays the files out as the diff view does at each width, with every file expanded.
    private func layOut(_ files: [DiffFile], _ what: String) {
        let clock = ContinuousClock()
        for width in widths {
            var rows = 0
            var height = 0.0
            let duration = clock.measure {
                let numberColumns = DiffLayout.numberColumns(of: files)
                let style = DiffLayout.style(forWidth: width, metrics: metrics, numberColumns: numberColumns)
                let document = DiffDocument(files: files, collapsed: [], style: style)
                let layout = DiffLayout(document: document, files: files, metrics: metrics, width: width, numberColumns: numberColumns)
                rows = document.blocks.count
                height = layout.height
            }
            report("\(what), \(rows) rows laid out at \(Int(width)) points, \(Int(height)) points tall", duration)
        }
    }

    private func readCommit(_ tag: String) async throws -> CommitDetail? {
        guard let hash = try await hash(of: tag) else { return nil }
        let clock = ContinuousClock()
        var detail: CommitDetail?
        let duration = try await clock.measure {
            detail = try await CommitDetail.read(hash, options: DiffOptions(), running: run, readingPatch: readPatch)
        }
        guard let detail else { return nil }
        let kept = detail.files.reduce(0) { $0 + $1.patch.hunks.reduce(0) { $0 + $1.lines.count } }
        let leftOut = detail.files.count { $0.patch.content != .shown }
        report("\(tag): read \(detail.files.count) files, \(kept) lines kept, \(leftOut) files left out", duration)
        return detail
    }

    private func readWholeFile(_ file: ChangedFile, of tag: String) async throws -> DiffFile? {
        guard let hash = try await hash(of: tag) else { return nil }
        let clock = ContinuousClock()
        var read: DiffFile?
        let duration = try await clock.measure {
            read = try await CommitDetail.readFile(file, of: hash, options: DiffOptions(), readingPatch: readPatch)
        }
        report("\(tag): read \(file.path) whole, \(read?.patch.changedLines ?? 0) changed lines", duration)
        return read
    }

    @Test
    func aCommitChangingThousandsOfFiles() async throws {
        guard let detail = try await readCommit("many-files") else { return }
        layOut(detail.files, "many-files")
    }

    @Test
    func aVeryLargeFile() async throws {
        guard let detail = try await readCommit("large-file"), let file = detail.files.first else { return }
        guard let whole = try await readWholeFile(file.changed, of: "large-file") else { return }
        layOut([whole], "large-file shown")
    }

    @Test
    func aFileWithOneEnormousLine() async throws {
        guard let detail = try await readCommit("long-line"), let file = detail.files.first else { return }
        guard let whole = try await readWholeFile(file.changed, of: "long-line") else { return }
        layOut([whole], "long-line shown")
        let clock = ContinuousClock()
        let line = try #require(whole.patch.hunks.first?.lines.first)
        let duration = clock.measure {
            _ = LineWrap.wrap(Array(line.text.utf16), columns: 90)
        }
        report("long-line: wrapping one line of \(line.text.utf16.count) characters to draw it", duration)
    }

    @Test
    func aLargeImage() async throws {
        guard let detail = try await readCommit("large-image"), let file = detail.files.first?.changed else { return }
        let clock = ContinuousClock()
        for (side, object) in [("before", file.oldObject), ("after", file.newObject)] {
            let object = try #require(object)
            var pixels = CGSize.zero
            let duration = try await clock.measure {
                let data = try await run(.reading(["cat-file", "blob", object])).standardOutput
                pixels = await DiffImage.decode(data, byteCount: data.count).pixelSize ?? .zero
            }
            report("large-image: read and decoded \(side), \(Int(pixels.width)) × \(Int(pixels.height))", duration)
        }
    }
}
