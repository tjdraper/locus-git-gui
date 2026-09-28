import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Builds a repository with as much history as a performance check needs, through `git fast-import`,
// which writes a million commits in about a minute where committing them one by one would take hours.
// See Scripts/README.md.

struct Options {
    var folder = ""
    var commits = 100_000
    /// Lines of work running beside main at once, each merged back and restarted in turn, which is
    /// how wide the history's graph gets.
    var lanes = 8
    var branches = 50
    var remoteBranches = 0
    var tags = 100
    var writesCommitGraph = false
    var addsLargeChanges = false
    var workingChanges = 0
    var conflicts = 0
}

func parseOptions() -> Options {
    var options = Options()
    var arguments = CommandLine.arguments.dropFirst()
    func number(for flag: String) -> Int {
        guard let value = arguments.popFirst().flatMap(Int.init), value >= 0 else {
            fail("\(flag) needs a number")
        }
        return value
    }
    while let argument = arguments.popFirst() {
        switch argument {
        case "--commits": options.commits = number(for: argument)
        case "--lanes": options.lanes = number(for: argument)
        case "--branches": options.branches = number(for: argument)
        case "--remote-branches": options.remoteBranches = number(for: argument)
        case "--tags": options.tags = number(for: argument)
        case "--commit-graph": options.writesCommitGraph = true
        case "--large-changes": options.addsLargeChanges = true
        case "--working-changes": options.workingChanges = number(for: argument)
        case "--conflicts": options.conflicts = number(for: argument)
        case "--help", "-h": usage()
        default:
            guard options.folder.isEmpty, !argument.hasPrefix("-") else { fail("Unknown option \(argument)") }
            options.folder = argument
        }
    }
    guard !options.folder.isEmpty else { usage() }
    return options
}

func usage() -> Never {
    print("""
    Usage: swift Scripts/GenerateTestRepository.swift <new folder> [options]

      --commits <n>          Commits to make (default 100000)
      --lanes <n>            Lines of work beside main at once, merged back in turn (default 8)
      --branches <n>         Extra local branches pointing into the history (default 50)
      --remote-branches <n>  Branches under refs/remotes/origin (default 0)
      --tags <n>             Tags pointing into the history (default 100)
      --commit-graph         Write a commit-graph file afterwards, as `git gc` would
      --large-changes        End main with commits whose diffs are hard to show, tagged perf/…:
                             thousands of files, a huge file, one enormous line, a large image
      --working-changes <n>  Leave <n> changed files and <n> untracked files in the working tree,
                             in work/, for the working area's performance check
      --conflicts <n>        Leave a merge stopped on <n> conflicted files in conflicts/, and on
                             conflicts/large.txt, 200,000 lines with 1,000 conflicts
    """)
    exit(0)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

@discardableResult
func git(_ arguments: [String], in folder: URL, input: ((FileHandle) -> Void)? = nil) -> Int32 {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = folder
    let pipe = Pipe()
    if input != nil {
        process.standardInput = pipe
    }
    do {
        try process.run()
    } catch {
        fail("Couldn’t run git: \(error.localizedDescription)")
    }
    if let input {
        input(pipe.fileHandleForWriting)
        try? pipe.fileHandleForWriting.close()
    }
    process.waitUntilExit()
    return process.terminationStatus
}

/// Collects the stream in memory and hands it to fast-import a megabyte at a time.
final class Stream {
    private let handle: FileHandle
    private var buffer = Data()

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    func write(_ text: String) {
        write(Data(text.utf8))
    }

    func write(_ data: Data) {
        buffer.append(data)
        if buffer.count > 1 << 20 {
            flush()
        }
    }

    /// `data` blocks give their length in bytes, not characters.
    func data(_ text: String) {
        write("data \(text.utf8.count)\n\(text)\n")
    }

    func flush() {
        handle.write(buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}

let authors = [
    "Ada Lovelace", "Grace Hopper", "Alan Turing", "Katherine Johnson", "Linus Torvalds", "Margaret Hamilton",
    "Dennis Ritchie", "Barbara Liskov", "Ken Thompson", "Frances Allen", "José Valim", "Zoë Kravitz",
]

func person(_ index: Int, at time: Int) -> String {
    let name = authors[index % authors.count]
    let email = name.lowercased().replacingOccurrences(of: " ", with: ".")
        .applyingTransform(.stripDiacritics, reverse: false) ?? "someone"
    return "\(name) <\(email)@example.com> \(time) +0000"
}

let options = parseOptions()
let folder = URL(filePath: options.folder, directoryHint: .isDirectory)
guard !FileManager.default.fileExists(atPath: folder.path) else {
    fail("\(folder.path) already exists")
}
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
guard git(["init", "--quiet", "--initial-branch=main"], in: folder) == 0 else { fail("git init failed") }

let started = Date()
var marks: [Int] = []
let status = git(["fast-import", "--quiet"], in: folder) { handle in
    let stream = Stream(handle)
    var mark = 0
    var time = 946_684_800
    var mainTip: Int?
    var laneTips = [Int?](repeating: nil, count: options.lanes)
    let mergeInterval = max(options.lanes * 4, 1)

    func commit(on ref: String, from parent: Int?, merging other: Int? = nil, message: String, file: String?) {
        mark += 1
        time += 60
        stream.write("commit \(ref)\nmark :\(mark)\n")
        stream.write("author \(person(mark, at: time))\ncommitter \(person(mark, at: time))\n")
        stream.data(message)
        if let parent {
            stream.write("from :\(parent)\n")
        }
        if let other {
            stream.write("merge :\(other)\n")
        }
        if let file {
            stream.write("M 100644 inline \(file)\n")
            stream.data("Change \(mark)\n")
        }
        stream.write("\n")
        marks.append(mark)
    }

    for index in 0 ..< options.commits {
        // Each lane takes its turn being merged back into main, and starts again from main after.
        if options.lanes > 0, index % mergeInterval == mergeInterval - 1 {
            let merging = (index / mergeInterval) % options.lanes
            if let tip = laneTips[merging], let main = mainTip {
                commit(on: "refs/heads/main", from: main, merging: tip, message: "Merge lane \(merging) into main\n", file: nil)
                mainTip = mark
                laneTips[merging] = nil
                continue
            }
        }
        let lane = options.lanes == 0 ? -1 : index % (options.lanes + 1) - 1
        if lane >= 0, let from = laneTips[lane] ?? mainTip {
            commit(on: "refs/heads/lane-\(lane)", from: from, message: "Work on lane \(lane), change \(index)\n", file: "lane-\(lane).txt")
            laneTips[lane] = mark
        } else {
            commit(on: "refs/heads/main", from: mainTip, message: "Change \(index) on main\n", file: "main.txt")
            mainTip = mark
        }
    }

    /// Spread evenly through the history, newest first.
    func spread(_ count: Int, _ make: (Int, Int) -> String) {
        guard count > 0, !marks.isEmpty else { return }
        for index in 0 ..< count {
            let target = marks[marks.count - 1 - (index * marks.count / count)]
            stream.write("reset \(make(index, target))\nfrom :\(target)\n\n")
        }
    }
    if options.addsLargeChanges {
        mainTip = addLargeChanges(to: stream, after: mainTip, mark: &mark, time: &time)
    }

    spread(options.branches) { index, _ in "refs/heads/topic/branch-\(index)" }
    spread(options.remoteBranches) { index, _ in "refs/remotes/origin/topic/branch-\(index)" }
    spread(options.tags) { index, _ in "refs/tags/v\(options.tags - index).0" }
    if let mainTip, options.remoteBranches > 0 {
        stream.write("reset refs/remotes/origin/main\nfrom :\(mainTip)\n\n")
    }
    stream.flush()
}
guard status == 0 else { fail("git fast-import failed") }

/// Commits on main whose diffs are hard to show, each tagged so a performance check can find it.
func addLargeChanges(to stream: Stream, after parent: Int?, mark: inout Int, time: inout Int) -> Int? {
    var tip = parent
    func commit(_ message: String, tag: String? = nil, files: [(path: String, contents: Data)]) {
        mark += 1
        time += 60
        stream.write("commit refs/heads/main\nmark :\(mark)\n")
        stream.write("author \(person(mark, at: time))\ncommitter \(person(mark, at: time))\n")
        stream.data(message + "\n")
        if let tip {
            stream.write("from :\(tip)\n")
        }
        for file in files {
            stream.write("M 100644 inline \(file.path)\ndata \(file.contents.count)\n")
            stream.write(file.contents)
            stream.write("\n")
        }
        stream.write("\n")
        tip = mark
        if let tag {
            stream.write("reset refs/tags/perf/\(tag)\nfrom :\(mark)\n\n")
        }
    }
    func lines(_ count: Int, changing every: Int? = nil, _ line: (Int) -> String) -> Data {
        Data((0 ..< count).map { index in
            (every.map { index % $0 == 0 } ?? false ? "changed " : "") + line(index) + "\n"
        }.joined().utf8)
    }

    let manyFiles = 5000
    let fileLines = { (index: Int, changing: Bool) in
        lines(20, changing: changing ? 4 : nil) { "Line \($0) of file \(index), with enough words to be a typical line of code" }
    }
    commit("Add many files", files: (0 ..< manyFiles).map { ("many/file-\($0).txt", fileLines($0, false)) })
    commit("Change many files", tag: "many-files", files: (0 ..< manyFiles).map { ("many/file-\($0).txt", fileLines($0, true)) })

    let largeLines = 200_000
    commit("Add a large file", tag: "large-file-added", files: [("large.txt", lines(largeLines) { "Line \($0) of a large file" })])
    commit("Change a large file", tag: "large-file", files: [("large.txt", lines(largeLines, changing: 10) { "Line \($0) of a large file" })])

    let longLine = { (seed: Int) in
        Data((String(repeating: "var a\(seed)=function(b){return b+1};", count: 150_000) + "\n").utf8)
    }
    commit("Add a minified file", files: [("minified.js", longLine(1))])
    commit("Change a minified file", tag: "long-line", files: [("minified.js", longLine(2))])

    commit("Add a large image", files: [("large.png", image(width: 8000, height: 6000, seed: 1))])
    commit("Change a large image", tag: "large-image", files: [("large.png", image(width: 8000, height: 6000, seed: 2))])
    return tip
}

/// A PNG of coloured blocks, which compresses poorly enough to be many megabytes.
func image(width: Int, height: Int, seed: UInt64) -> Data {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("Couldn’t draw an image") }
    var random = seed
    func next() -> Double {
        random = random &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(random >> 11) / Double(1 << 53)
    }
    for y in stride(from: 0, to: height, by: 16) {
        for x in stride(from: 0, to: width, by: 16) {
            context.setFillColor(CGColor(red: next(), green: next(), blue: next(), alpha: 1))
            context.fill(CGRect(x: x, y: y, width: 16, height: 16))
        }
    }
    let data = NSMutableData()
    guard let cgImage = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        fail("Couldn’t write an image")
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}
git(["reset", "--hard", "--quiet"], in: folder)
if options.writesCommitGraph {
    git(["commit-graph", "write", "--reachable"], in: folder)
}
if options.workingChanges > 0 {
    addWorkingChanges(options.workingChanges, in: folder)
}
if options.conflicts > 0 {
    addConflicts(options.conflicts, in: folder)
}

/// Commits `count` files, then changes every one and adds as many untracked files beside them.
func addWorkingChanges(_ count: Int, in folder: URL) {
    let work = folder.appending(path: "work")
    try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    func write(_ name: String, _ index: Int, changed: Bool) {
        let text = (0 ..< 20).map { line in
            (changed && line % 5 == 0 ? "changed " : "") + "Line \(line) of \(name) \(index), with enough words to be a typical line"
        }.joined(separator: "\n") + "\n"
        try? Data(text.utf8).write(to: work.appending(path: "\(name)-\(index).txt"))
    }
    for index in 0 ..< count {
        write("tracked", index, changed: false)
    }
    git(["add", "work"], in: folder)
    git(["-c", "user.name=Test Author", "-c", "user.email=author@example.com", "commit", "--quiet", "--message", "Add files to change"], in: folder)
    for index in 0 ..< count {
        write("tracked", index, changed: true)
        write("untracked", index, changed: false)
    }
}
/// Commits `count` small files and one large one, changes the same lines of each on `main` and on a
/// branch, and merges the branch, which stops on every file.
func addConflicts(_ count: Int, in folder: URL) {
    let conflicts = folder.appending(path: "conflicts")
    try? FileManager.default.createDirectory(at: conflicts, withIntermediateDirectories: true)
    let author = ["-c", "user.name=Test Author", "-c", "user.email=author@example.com"]
    func write(side: String?) {
        for index in 0 ..< count {
            let text = (0 ..< 20).map { line in
                (line % 5 == 0 ? side.map { "\($0) changed " } ?? "" : "") + "Line \(line) of file \(index), with enough words to be typical"
            }.joined(separator: "\n") + "\n"
            try? Data(text.utf8).write(to: conflicts.appending(path: "file-\(index).txt"))
        }
        let large = (0 ..< 200_000).map { line in
            (line % 200 == 100 ? side.map { "\($0) changed " } ?? "" : "") + "Line \(line) of the large file, with enough words to be typical"
        }.joined(separator: "\n") + "\n"
        try? Data(large.utf8).write(to: conflicts.appending(path: "large.txt"))
    }
    write(side: nil)
    git(["add", "conflicts"], in: folder)
    git(author + ["commit", "--quiet", "--message", "Add files that will conflict"], in: folder)
    git(["switch", "--quiet", "--create", "incoming"], in: folder)
    write(side: "incoming")
    git(author + ["commit", "--quiet", "--all", "--message", "Change them on a branch"], in: folder)
    git(["switch", "--quiet", "-"], in: folder)
    write(side: "main")
    git(author + ["commit", "--quiet", "--all", "--message", "Change them on main"], in: folder)
    git(author + ["merge", "--quiet", "--no-edit", "incoming"], in: folder)
}
print("Made \(options.commits) commits in \(folder.path) in \(Int(Date().timeIntervalSince(started))) seconds")
