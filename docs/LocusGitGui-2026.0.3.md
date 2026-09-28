## 2026.0.3

The first beta you can use for real work. Earlier builds only tested installing and updating.

### Added

- **Setup checklist** that finds the Git executable that Terminal uses, or lets you choose another, offers to install Apple’s Command Line Tools when there’s no Git, and asks about automatic update checks.
- **Your shell’s environment for Git**, read from your login shell, so hooks, signing, and `git lfs` find what they find in Terminal.
- **Opening repositories** from File > Open, by dropping folders on the Dock icon, or with `open -a "Locus Git Gui"` from Terminal. A folder inside a repository opens the repository.
- **Dashboard** of every repository opened before, with fuzzy search, display names, missing repositories marked with Locate…, and Open Recent in the File menu and the Dock menu.
- **Native tabs and window restoration**, following macOS’s own settings. Each repository remembers its selection, column widths, filters, scroll positions, and the windows opened from it.
- **Sidebar** of branches, remotes, tags, and stashes, with a filter, pinned items, ahead and behind counts, type-to-select, double-click to check out, and dragging a branch onto another to merge or rebase.
- **Command palette** (⌘P) that reaches every menu command, and jumps to any branch, tag, or stash.
- **History** with a commit graph that stays fast and snappy on histories of a million commits or more, and Find by message, hash, author, or changes. A commit shows its author, dates, parents, signature, and message, with Markdown in message bodies.
- **Diffs** side by side or inline, with changed words highlighted, file headers that stay in view, images before and after, large files kept out of the way until asked for, and Ignore Whitespace and context lines in the View menu. Open in Editor, Reveal in Finder, and Copy Path work from any diff.
- **Windows of their own** for a commit, a file’s changes, a branch’s history, Uncommitted Changes, and Activity, which lists every Git command the app has run.
- **Staging** by file, hunk, or selected lines, with Space to stage the current file, and several files picked to stage, unstage, or discard together, including Stage Selected in a group’s heading. The group headings stay in view as their files scroll past.
- **Discarding** that moves the discarded version to the Trash, so Put Back returns it.
- **Committing** with a subject and body kept apart, ⌘Return to commit, Amend Last Commit, and a failed hook’s output shown without losing the message.
- **Fetch, pull, and push** with progress and a way to stop them, force push with `--force-with-lease`, and optional automatic fetch in the background.
- **Credential prompts** for SSH keys, passphrases, new hosts, and HTTPS tokens, as sheets on the window that needs them. Git’s credential helper and your SSH agent keep what you enter.
- **Remotes and tags:** add, edit, and remove remotes, push and delete tags on a remote, and delete remote branches.
- **Clone Repository…** and **Create Repository…** from the File menu, the palette, and the dashboard.
- **Branch, commit and stash commands:** check out, create, rename, and delete branches, set upstreams, merge, rebase, cherry-pick, revert, soft, mixed, and hard reset, reword or edit a commit, tags, and stash, apply, pop, and drop.
- **Operations stopped partway**, such as a merge with conflicts, with Continue, Skip, and Abort in the toolbar and the Commit menu.
- **Merge conflict window** showing both sides above an editable result, with a side taken per conflict from the keyboard, and a plain choice for conflicts that aren’t about content.
- **A status in the toolbar** showing what Git is doing, a stopped operation, or a notice naming the commit that brings back what a command took away. It never pushes the window’s contents around. Click it for the Notices panel, which also opens as a window.
- **Plain explanations for common failures**, such as a leftover lock file, a rejected push, a failed sign-in, or a network problem, each with a next step and Git’s own output in full.
- **Settings** for which Git to use, which path ⌥⌘C copies, the diff’s layout, font, and defaults, automatic fetch and how often, and updates and betas.

### Changed

- Updates no longer interrupt. A found update waits behind an Update Available button on the dashboard and in each repository window, and a badge on the Dock icon. After two weeks, the update window opens to prompt a little harder.
- Updates are no longer downloaded and installed by themselves. The download starts when you click Install Update.
