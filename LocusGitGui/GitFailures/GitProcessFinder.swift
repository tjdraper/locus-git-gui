import Darwin
import Foundation

/// Finds Git processes working in a repository, so a lock is only offered for removal when nothing
/// can be holding it. A Git process runs in the repository it works on, so its working directory
/// gives it away.
nonisolated enum GitProcessFinder {
    /// `excludingChildrenOf` leaves out the ones a process started itself, such as the app's own
    /// reads, when what matters is whether something else is working in the repository.
    static func processes(workingIn folders: [URL], excludingChildrenOf parent: pid_t? = nil) -> [pid_t] {
        let paths = folders.map { ResolvedPath.of($0).path }
        return allProcessIdentifiers().filter { processIdentifier in
            guard isGit(processIdentifier), let directory = workingDirectory(of: processIdentifier) else {
                return false
            }
            if let parent, parentIdentifier(of: processIdentifier) == parent {
                return false
            }
            return paths.contains { directory == $0 || directory.hasPrefix($0 + "/") }
        }
    }

    private static func allProcessIdentifiers() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        // Room for processes started between the two calls.
        var identifiers = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&identifiers, Int32(identifiers.count * MemoryLayout<pid_t>.size))
        return Array(identifiers.prefix(Int(max(count, 0))))
    }

    /// `git` itself, and helpers it starts such as `git-remote-https`.
    private static func isGit(_ processIdentifier: pid_t) -> Bool {
        var name = [UInt8](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(processIdentifier, &name, UInt32(name.count)) > 0,
              let processName = String(bytes: name.prefix { $0 != 0 }, encoding: .utf8)
        else {
            return false
        }
        return processName == "git" || processName.hasPrefix("git-")
    }

    private static func parentIdentifier(of processIdentifier: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(processIdentifier, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return nil
        }
        return pid_t(info.pbi_ppid)
    }

    /// Nil for processes owned by someone else, which macOS doesn't let the app look into.
    private static func workingDirectory(of processIdentifier: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(processIdentifier, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else {
            return nil
        }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { buffer in
            String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8)
        }
    }
}
