import AppKit

/// Adds, edits and removes the repository's remotes. A remote that's added is fetched straight
/// away, so its branches show in the sidebar.
final class RemoteEditingWorkflow: NSObject {
    static let actions: Set<Selector> = [#selector(addRemote(_:))]

    /// As of the last refresh.
    var remotes: [String] = []
    var repositoryWindow: (() -> NSWindow?)?

    private let commands: RepositoryCommandRunner
    private let queue: WorkingAreaCommandQueue
    private let runner: RemoteOperationRunner
    private let sync: RemoteSyncWorkflow

    init(commands: RepositoryCommandRunner, queue: WorkingAreaCommandQueue, runner: RemoteOperationRunner, sync: RemoteSyncWorkflow) {
        self.commands = commands
        self.queue = queue
        self.runner = runner
        self.sync = sync
    }

    /// Named `origin` when it's the first, as a clone's is, and with an address from the clipboard
    /// when it holds one.
    @objc func addRemote(_: Any?) {
        guard let window = NSApp.keyWindow ?? repositoryWindow?(), ReadOnlyLock.allowsChange(in: window) else { return }
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        var sheet: NSWindow?
        let close = { [weak window] in
            if let window, let sheet {
                window.endSheet(sheet)
            }
        }
        sheet = RemoteForm.present(RemoteForm(
            title: "Add Remote",
            confirmTitle: "Add",
            name: remotes.isEmpty ? "origin" : "",
            url: RemoteURL.looksLikeRemote(clipboard) ? clipboard.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            takenNames: Set(remotes),
            onSave: { [weak self] name, url in
                close()
                self?.add(name, url: url, from: window)
            },
            onCancel: close
        ), on: window)
    }

    func edit(_ remote: String, from window: NSWindow?) {
        guard ReadOnlyLock.allowsChange(in: window ?? repositoryWindow?()) else { return }
        guard let window = window ?? repositoryWindow?() else { return }
        Task { [weak self] in
            guard let self else { return }
            let currentURL = await url(of: remote) ?? ""
            var sheet: NSWindow?
            let close = {
                if let sheet {
                    window.endSheet(sheet)
                }
            }
            sheet = RemoteForm.present(RemoteForm(
                title: "Edit Remote “\(remote)”",
                confirmTitle: "Save",
                name: remote,
                url: currentURL,
                takenNames: Set(remotes).subtracting([remote]),
                onSave: { [weak self] name, url in
                    close()
                    self?.change(remote, to: name, url: url == currentURL ? nil : url)
                },
                onCancel: close
            ), on: window)
        }
    }

    /// Asks first, and gives the address, which is what adding it back needs.
    func remove(_ remote: String, from window: NSWindow?) {
        guard ReadOnlyLock.allowsChange(in: window ?? repositoryWindow?()) else { return }
        Task { [weak self] in
            guard let self else { return }
            let address = await url(of: remote)
            let alert = NSAlert()
            alert.messageText = "Remove the remote “\(remote)”?"
            alert.informativeText = [
                "Its remote branches go from this repository, and branches that track them lose their upstream.",
                "The remote itself isn’t changed, and adding it again brings them back",
            ].joined(separator: " ") + (address.map { ": \($0)" } ?? ".")
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
            guard await AlertPresentation.run(alert, on: window ?? repositoryWindow?()) == .alertFirstButtonReturn else { return }
            run(RemoteCommand.removeRemote(remote), failing: "Git couldn’t remove the remote “\(remote)”.")
        }
    }

    var canEdit: Bool {
        !runner.isBusy
    }

    private func add(_ name: String, url: String, from window: NSWindow) {
        queue.run("Git couldn’t add the remote “\(name)”.") { [weak self, commands] in
            let command = RemoteCommand.addRemote(name, url: url)
            let result = try await commands.run(command)
            guard result.status == 0 else { throw WorkingAreaStaging.Failure(command: command, result: result) }
            guard let self else { return }
            // Ahead of the refresh that lists it, which the fetch doesn't wait for.
            sync.state.remotes.append(name)
            sync.fetch(name, from: window)
        }
    }

    private func change(_ remote: String, to name: String, url: String?) {
        queue.run("Git couldn’t change the remote “\(remote)”.") { [commands] in
            var changes: [GitCommand] = []
            if let url {
                changes.append(RemoteCommand.setURL(of: remote, to: url))
            }
            if name != remote {
                changes.append(RemoteCommand.renameRemote(remote, to: name))
            }
            for command in changes {
                let result = try await commands.run(command)
                guard result.status == 0 else { throw WorkingAreaStaging.Failure(command: command, result: result) }
            }
        }
    }

    private func run(_ command: GitCommand, failing summary: String) {
        queue.run(summary) { [commands] in
            let result = try await commands.run(command)
            guard result.status == 0 else { throw WorkingAreaStaging.Failure(command: command, result: result) }
        }
    }

    private func url(of remote: String) async -> String? {
        guard let result = try? await commands.run(RemoteCommand.url(of: remote)), result.status == 0 else { return nil }
        return String(bytes: result.standardOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension RemoteEditingWorkflow: NSMenuItemValidation {
    func validateMenuItem(_: NSMenuItem) -> Bool {
        canEdit
    }
}
