import Foundation

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
        buffer.append(contentsOf: text.utf8)
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
    spread(options.branches) { index, _ in "refs/heads/topic/branch-\(index)" }
    spread(options.remoteBranches) { index, _ in "refs/remotes/origin/topic/branch-\(index)" }
    spread(options.tags) { index, _ in "refs/tags/v\(options.tags - index).0" }
    if let mainTip, options.remoteBranches > 0 {
        stream.write("reset refs/remotes/origin/main\nfrom :\(mainTip)\n\n")
    }
    stream.flush()
}
guard status == 0 else { fail("git fast-import failed") }
git(["reset", "--hard", "--quiet"], in: folder)
if options.writesCommitGraph {
    git(["commit-graph", "write", "--reachable"], in: folder)
}
print("Made \(options.commits) commits in \(folder.path) in \(Int(Date().timeIntervalSince(started))) seconds")
