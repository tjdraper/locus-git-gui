import Foundation
import os

/// The environment the user's login shell sets up, which Git and its hooks need to find what they
/// find in Terminal. An app opened from the Dock gets a bare environment without the shell's PATH.
nonisolated struct LoginShellEnvironment: Sendable {
    enum Source: Sendable, Equatable {
        case loginShell
        case launchEnvironment(because: Fallback)
    }

    enum Fallback: Error, Equatable {
        case timedOut
        case couldNotStart
        case exitedWithoutEnvironment(status: Int32)
    }

    /// Variables that describe the shell process itself rather than the user's setup.
    private static let shellOwnVariables: Set<String> = ["_", "SHLVL", "PWD", "OLDPWD"]

    private static let log = Logger(subsystem: "com.buzzingpixel.LocusGitGui", category: "LoginShell")

    let variables: [String: String]
    let source: Source

    static func capture(
        shell: URL = userShell(),
        launchEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: Duration = .seconds(10)
    ) async -> LoginShellEnvironment {
        let started = ContinuousClock.now
        let outcome = await withTaskGroup(of: Result<[String: String], Fallback>.self) { group in
            group.addTask { await read(from: shell, launchEnvironment: launchEnvironment) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .failure(.timedOut)
            }
            let first = await group.next() ?? .failure(.timedOut)
            group.cancelAll()
            return first
        }
        let elapsed = ContinuousClock.now - started

        switch outcome {
        case let .success(variables):
            log.info("Captured \(variables.count) variables from the login shell in \(elapsed, privacy: .public)")
            return LoginShellEnvironment(variables: variables, source: .loginShell)
        case let .failure(fallback):
            log.error("Using the launch environment after \(elapsed, privacy: .public): \(String(describing: fallback), privacy: .public)")
            return LoginShellEnvironment(variables: launchEnvironment, source: .launchEnvironment(because: fallback))
        }
    }

    /// `SHELL` is what Terminal starts. The account record is the same setting, for when the app
    /// was launched without it.
    static func userShell() -> URL {
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return URL(filePath: shell)
        }
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            return URL(filePath: String(cString: shell))
        }
        return URL(filePath: "/bin/zsh")
    }

    /// The environment printed between two copies of the marker, or nil until the second arrives.
    /// Shell startup files can print anything before it, and a background job they start can keep
    /// printing after.
    static func parse(_ output: Data, marker: String) -> [String: String]? {
        let markerData = Data(marker.utf8)
        guard let opening = output.range(of: markerData),
              let closing = output.range(of: markerData, in: opening.upperBound ..< output.endIndex)
        else {
            return nil
        }

        var variables: [String: String] = [:]
        for entry in output[opening.upperBound ..< closing.lowerBound].split(separator: 0) {
            guard let equals = entry.firstIndex(of: UInt8(ascii: "=")),
                  let name = String(bytes: entry[entry.startIndex ..< equals], encoding: .utf8),
                  let value = String(bytes: entry[entry.index(after: equals)...], encoding: .utf8),
                  !name.isEmpty,
                  !shellOwnVariables.contains(name)
            else {
                continue
            }
            variables[name] = value
        }
        return variables
    }

    /// Interactive as well as login, since most people set PATH in `.zshrc`, which only an
    /// interactive zsh reads. Stops listening as soon as the environment has been printed, since
    /// the shell can't be relied on to close its output.
    private static func read(
        from shell: URL,
        launchEnvironment: [String: String]
    ) async -> Result<[String: String], Fallback> {
        let marker = UUID().uuidString
        let process = ChildProcess(
            executableURL: shell,
            arguments: ["-l", "-i", "-c", "printf '\(marker)'; /usr/bin/env -0; printf '\(marker)'"],
            environment: launchEnvironment,
            currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
        )

        var output = Data()
        do {
            for try await event in process.stream() {
                switch event {
                case let .standardOutput(data):
                    output.append(data)
                    if let variables = parse(output, marker: marker) {
                        return .success(variables)
                    }
                case .standardError:
                    continue
                case let .exited(status):
                    return .failure(.exitedWithoutEnvironment(status: status))
                }
            }
        } catch {
            return .failure(.couldNotStart)
        }
        return .failure(.timedOut)
    }
}
