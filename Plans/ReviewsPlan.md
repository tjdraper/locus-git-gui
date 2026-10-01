# Reviews

A review is a list of the files that differ between two points in a repository. Each file is checked off as it's read, the checks are kept, and comments can be left on a file, on a line, or on the review as a whole. The main use is a feature branch checked against the branch it will merge into, such as a pull request branch against `production`, but either side can be any branch, tag, commit, or the uncommitted changes.

This isn't Git; it's built on top of Git. The high-level plan's Not planned list keeps pull requests and notes out of the app. Reviews are a deliberate exception: they're local to this Mac, need no hosting service, and only read the repository, apart from the hidden refs below.

Built (2026-10-01), all five steps of the build order, in `Reviews/`, with the diff view's inserts in `DiffView/`. Driven by script in the Debug build on a scratch repository, in light mode: New Review from the Review menu, the toolbar's popover, checking files off from the list, the header and the menu, a new commit clearing one check and showing only the changes since, a branch's new commits followed with the window open, a working-tree review with an untracked file checked and then edited, the review window coming back after a relaunch with its file and checks, a file comment and a line comment, the line comment following its line down when a line was added above it, a reply, resolving and its folded line, the Comments page, Copy Comments as Markdown, and the lock with `--expire-trial`. Not yet tried: dark mode, a large repository, Rename… and Delete…, a review left open across a fetch that moves a remote branch, a deleted branch in the app (covered by a test), an outdated comment in the app (its following is covered by tests), Space in the list, and Move to the Latest Commit On.

## The two points

- Each side of a review is a point, and a point is one of:
  - **A local branch** or **a remote branch** (`origin/feature-x`). It follows the branch: new commits, a pull, a fetch, or a force push move the review with it.
  - **A tag.** It follows the tag, since tags can be moved (slice 11's force-pushed tag).
  - **A commit.** It stays where it is until moved by hand.
  - **The working tree.** Everything uncommitted, staged and unstaged, including untracked files that aren't ignored.
- A review of uncommitted changes is HEAD against the working tree. HEAD follows the checked-out commit, so committing takes those files out of the review.
- Any pair works, so `production` against the working tree shows everything on the current branch, committed or not.
- When both sides are commits or refs, the review compares the head side against the point where the two split (the merge base), as a pull request does. New commits on `production` then don't show as changes in the review. Merging `production` into the feature branch moves the merge base, and the files that merge brought in leave the review.
- Creating a review starts with the head side as the checked-out branch and the base as the remote's default branch (`refs/remotes/origin/HEAD`), both changeable before and after. The default name is "head → base", and can be changed.
- When a followed branch is deleted (a merged pull request whose branch was pruned on fetch), the review keeps the last commit it knew and says the branch is gone. Either side can then be pointed somewhere else.
- A commit side can be moved by hand: pick another commit from the history, or move to the latest commit of a branch that contains it.

## Revisions

- Each time either side, or the merge base, changes, the review records a revision: the two commits, the merge base, and when. A pull request's "versions" in GitLab are the same idea.
- "Changes since reviewed" and comment anchors refer to file contents that have to outlive a force push or a rebase, which Git deletes once nothing points at them.
  - Built differently from the plan: checks and comments record the contents (blobs) themselves rather than the commits, so the commits needn't be kept. Each review has one hidden ref, `refs/locus/reviews/<review id>`, pointing at a tree that holds every blob its checks and comments name (`ReviewKeptObjects`). A tree rather than commits keeps it out of `git log --all` in Terminal, and one ref per review keeps the ref list short.
  - Hidden refs are local. They aren't under `refs/heads` or `refs/tags`, so `git push` and `git clone` don't carry them. `git push --mirror` would, and that's accepted.
  - The sidebar, the palette, and anything else that lists refs leave `refs/locus/` out, since every ref list in the app names `refs/heads`, `refs/remotes` and `refs/tags`.
  - Deleting a review deletes its ref.
- The working tree isn't a commit. When a working-tree file is checked off or commented on, its contents are written into the repository with `git hash-object -w` and kept like any other blob. That replaced the planned snapshot commit through a temporary index, which would have stored every file to keep one.
- Writing refs touches the Git directory, which the refresh watches. A revision is only recorded when a point is somewhere new, so the refresh the app's own ref causes records nothing.

## Checking off files

- A file is checked off as a whole, with no checks on parts of a file.
- A check records the file's fingerprint: its path, any rename, and the blob on each side. `git diff --raw -z` gives the blobs for every file at once without reading their contents, which keeps this cheap on a large review. Working-tree files have no blob until `git hash-object --stdin-paths` computes them, and only for changed files.
- When a later revision gives a checked file a different fingerprint, the check clears and the file is marked as changed since it was reviewed. A rebase or force push that leaves a file's contents the same leaves its check alone.
- A file changed since it was reviewed can show its whole diff, or only the changes since it was checked: the file as it was checked against the file now (`git diff <blob> <blob>`). It shows only the changes since unless the header's checkbox says otherwise.
  - When only the base side changed, there's no "since" to show, so it shows the whole diff.
- New files joining the review come in unchecked. Files that no longer differ leave it, along with their checks. Their comments stay on the review, listed on its Comments page.
- A review is done when every file is checked. A new revision that unchecks a file, or adds one, makes it in progress again.
- Renames show both paths, deleted files show what was removed, binary files and images use the diff view's existing handling, and a change to only a file's permissions says so. Each is checked off the same way.

## Comments

GitLab merge request comments are the model.

- Three places to comment: on the review as a whole, on a file, and on a line or a range of lines on either side of the diff.
- A comment starts a thread. Threads take replies and can be resolved and reopened. Comments can be edited and deleted.
- The body is Markdown, shown the way commit bodies are (slice 11).
- Comments live only on this Mac and nobody else sees them. Copy Comments as Markdown puts every unresolved thread on the clipboard, with its file and line, to paste into a pull request, an issue, or a message.
- A line comment is anchored to the revision, the file, the side, and the line, along with the line's text. When a new revision changes the file, the anchor follows the line through the diff between the old and new contents. If the line itself changed or was removed, the thread is marked outdated and shows the lines it was left on, as GitLab does.
- Unresolved threads don't stop a review from being done. The list shows their count beside the progress.

## The review window

Changed after trying it (2026-10-01): the two points moved into the window's toolbar, with Comment on Review and Rename Review beside them. The list lost the sidebar's grey, and takes several files at once: the right column then says how many are picked and offers to mark them all reviewed or not, and Space and the Review menu act on them all. Each file has a context menu: marking it, commenting on it, only its changes since reviewed, and the diff's own Open in Editor, Reveal in Finder and Copy Path commands. The diff has no collapse control, since files are picked on the left. A comment button shows beside the line under the pointer, and one on the file's header comments on the file. Comments are written in text areas, where Return starts a new line and ⌘Return sends, and are shown with their line breaks. Threads and the Comments page use the column's whole width.

- Two columns. Files on the left, the selected file's diff on the right.
- One window per review. Opening a review that's already open brings its window forward.
- Above the columns: the review's name, the two points with a picker for each, the revision, and the progress ("12 of 30"). The two points can be swapped.
- The file list shows each file's path, its kind of change, a checkbox, a mark when it changed since it was reviewed, and its count of unresolved threads. A filter hides checked files.
- The diff is slice 8's diff view, showing one file, with a checkbox in its header. Its choice between the whole diff and the changes since reviewed sits there too, when the file has both.
- From the keyboard: check the selected file and move to the next unchecked one, next and previous file, next unchecked file, and starting a comment on the line under the cursor. Shortcuts are chosen when built, and stay off ⌘-number and ⌃⌘-arrows.
- Comment threads sit inline in the diff, under the lines they're on. The diff draws its own rows (see the high-level plan's Decisions), so a thread is a row of its own height holding ordinary views. This is the riskiest part of the feature and gets tried first.
- The window's place, the selected file, each file's scroll position, the filter, and which review windows were open all come back after closing and relaunching, the same as the rest of the app.

## The list of reviews

- A Reviews button in each repository window's toolbar opens a popover listing that repository's reviews, with New Review… and a button that opens the list in a window of its own (one per repository).
- Each review records when it was created, when it was last opened, and when its state last changed. A state change is a check, an uncheck, a comment, a rename, or a new revision. Opening a review isn't.
- The list is sorted by the last state change, newest first. It shows reviews opened in the last 90 days, with Show Older Reviews for the rest.
- A row shows the name, the two points, the progress, unresolved threads, and a mark when files have changed since they were reviewed. A done review shows that it's done.
- Each review has Open, Rename…, and Delete… in a context menu and in the menu bar. Delete confirms first: Return confirms and Escape cancels.
- New Review…, Show Reviews, and the review window's own commands go through the command catalog, so they're in the menus and the palette.

## Storage

- Reviews are kept in Application Support, one JSON file per review in a folder for the repository. They're tied to the repository the same way `RepositoryViewStateFiles` ties view state, and are written off the main actor shortly after they stop changing, in the same manner.
- One file per review, since comments make a review grow, and a change to one review shouldn't rewrite them all.
- They don't sync through iCloud, and they don't go into the repository.

## When the trial has ended

- Reviews don't work without a license. The toolbar button, New Review…, and opening a review all go to the purchase sheet, like any locked command.
- A review window open when the trial ends shows the lock in place of the review.
- Reviews and their hidden refs are kept, and work again once a license arrives.

## Tests

The pure parts go in the test target: the fingerprints and which checks a new revision clears, recording revisions, moving a comment's anchor through a diff and deciding when it's outdated, which reviews the list shows and in what order, and when a review is done. Fixtures are built with the real `git`, as the parsers' are, including a force push, a rebase that leaves files alone, and a merge from the base branch.

## Build order

1. Reviews and their storage, the two points, revisions, and hidden refs. Inline rows in the diff tried as a spike, since comments depend on them.
2. The review window: the file list, checks, the diff, progress, the filter, and view state.
3. The toolbar button, the popover and its window, naming and deleting, the dates, menus and the palette, and the lock.
4. Following branches: new revisions as they arrive, changes since reviewed, the gone branch, and moving a commit side.
5. Comments on the review and on files, then on lines, with anchors that follow and outdated threads.

Each step is seen in light and dark mode, and tried against a large repository, before it's done (see the high-level plan's Decisions on performance).

## Pull requests and merge requests later

Reviews stay local for now, but a future version may start a review from a GitHub pull request or a GitLab merge request and send its comments back (see the high-level plan's Future versions). So that doesn't need a rewrite:

- A review's points, revisions, and comments are plain data with no knowledge of the windows that show them.
- A line comment's anchor is the file path, the side, the line number on that side, and the commits of the revision it was left on. Both GitHub and GitLab place a comment with those.
- Threads, replies, and resolving map onto both services' threads, and every review, thread, and comment has a stable id that a service's id can be stored beside later.
- Where a review came from is a field of its own, local for every review today.

## Open questions

None for now. Copy Comments as Markdown is the only way comments leave the app until pull requests are connected.
