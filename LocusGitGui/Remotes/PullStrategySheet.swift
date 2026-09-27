import AppKit
import SwiftUI

/// Asked when a pull finds the branch and its upstream have diverged and the repository doesn't say
/// whether to merge or rebase. The choice can be kept as `pull.rebase` in the repository's own
/// configuration, where Git in Terminal reads it too.
struct PullStrategySheet: View {
    struct Choice {
        let strategy: RemoteCommand.PullStrategy
        let remember: Bool
    }

    /// Commits on each side that the other doesn't have.
    struct Divergence {
        let branchOnly: Int
        let upstreamOnly: Int
    }

    let branch: String
    let upstream: String
    let divergence: Divergence?
    let finish: (Choice?) -> Void

    @State private var remember = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Text("“\(branch)” and “\(upstream)” have diverged")
                        .font(.headline)
                    Text(explanation)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle("Always do this when pulling in this repository", isOn: $remember)
            HStack {
                Spacer()
                Button("Cancel") { finish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Rebase") { finish(Choice(strategy: .rebase, remember: remember)) }
                Button("Merge") { finish(Choice(strategy: .merge, remember: remember)) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var explanation: String {
        let sides = divergence.map { divergence in
            "“\(branch)” has \(Self.commits(divergence.branchOnly)) that “\(upstream)” doesn’t, and “\(upstream)” has "
                + "\(Self.commits(divergence.upstreamOnly)) that “\(branch)” doesn’t. "
        } ?? ""
        return sides + "Merge them with a merge commit, or rebase this branch’s commits onto “\(upstream)”?"
    }

    private static func commits(_ count: Int) -> String {
        count == 1 ? "1 commit" : "\(count) commits"
    }

    static func readDivergence(running run: (GitCommand) async throws -> ChildProcess.Result) async -> Divergence? {
        guard let result = try? await run(RemoteCommand.divergence), result.status == 0,
              let output = String(bytes: result.standardOutput, encoding: .utf8),
              case let counts = output.split(whereSeparator: \.isWhitespace).compactMap({ Int($0) }),
              counts.count == 2
        else { return nil }
        return Divergence(branchOnly: counts[0], upstreamOnly: counts[1])
    }

    static func ask(branch: String, upstream: String, divergence: Divergence?, on window: NSWindow) async -> Choice? {
        await withCheckedContinuation { continuation in
            let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
            sheet.contentViewController = NSHostingController(rootView: PullStrategySheet(
                branch: branch,
                upstream: upstream,
                divergence: divergence
            ) { [weak window, weak sheet] choice in
                if let window, let sheet {
                    window.endSheet(sheet)
                }
                continuation.resume(returning: choice)
            })
            window.beginSheet(sheet)
        }
    }
}
