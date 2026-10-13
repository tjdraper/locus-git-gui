## 2026.0.4

### Added

- **Reviews** that check off, file by file, what differs between two points in a repository, such as a feature branch against the branch it will merge into. Either side can be a branch, tag, commit, or uncommitted changes, and a branch or tag side moves with it. Start one with New Review or the Reviews button in the toolbar, and see them all with Show Reviews (⇧⌘R).
- **Checks that keep up with the branch.** A file that changes after it was checked off is unchecked and marked, and can show only what changed since. A rebase or force push that leaves a file the same keeps its check.
- **Review comments** on the review, a file, or a line, written in Markdown, with replies and resolving. A line comment follows its line as the file changes, and is marked outdated when the line itself changes. Copy Comments as Markdown puts the unresolved ones on the clipboard.
- Reviews and their comments stay on the Mac. The file contents they refer to are kept under `refs/locus/`, which `git push` and `git clone` don’t carry.
- **Force Push** when pushing a tag the remote already has replaces the remote’s tag with the force-pushed tag.
- **A 30-day trial**, starting the first time you open this version, counted down in the toolbar and on the dashboard, and shown in a new License pane in Settings. Reinstalling doesn’t restart it, and your Macs on the same Apple ID share one trial. When it ends, repositories become read-only: history, changes, and status still show, but changing a repository, talking to a remote, and reviews need a license.

### Changed

- The diff marks the current file with only its accent bar, so it no longer looks selected.

### Known Issues

- Licenses can’t be bought yet. Purchase… explains the trial and what a license unlocks, and buying arrives in a later beta.
