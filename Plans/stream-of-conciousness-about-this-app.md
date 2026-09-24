We're going to build a Mac-assed Mac app Git Gui.

As far as Mac Apps go, there's a lot I like about Tower (Git Tower). It's a very nice looking and Mac dedicated Mac app. In some ways, it's very Mac-assed. But it tries to do too many features that aren't really Git, and it's not friendly for more keyboard focused workflows.

My current daily driver is Sublime Merge. I like the command pallet which let's me drive a lot from the keyboard (though not everything, which is a complaint). But it's an ugly-ass app, it does not feel at home on the Mac AT ALL.

I want this app to feel at home on the Mac. I want it to be very keyboard friendly. And I want it to focus on doing Git things, not features that aren't in Git (which Tower often does).

A git repo's window should generally be a three column layout.

Left column/sidebar shows branches, remotes, tags, and stashes.

Middle column shows commits history. It should ONLY show the commit history for the selected item in the left sidebar (note that it should show selection if there is one, or the currently checked out branch or HEAD otherwise). At the top of the commit history should be the working area that shows unstaged, untracked, uncommitted changes (this is very similar to Sublime Merge, we're just going to do it in a very Mac-assed way).

The right column should show the files/diffs of the selected commit or working area. We'll work on the exact presentation of this. When a commit is selected, at the top we'll show info about the commit and the commit subject/message (the message will be limited to first line/subject and can be clicked to expand to the full message if there's more). When viewing the working area, There will be an input for the commit message.

Files/diffs should be expandable and collapsable. We should be able to open a file in the editor.

We should have a command pallet type thing that is brought up with cmd + p (or cmd + shift + p).

The title bar should show the full path to the git directory that is open, and the branch that is currently checked out, and what state things are in (clean, uncommitted changes, staged changes, etc. — in fact, we should use the Mac's convention of having a dot in the red close button when we're not in a clean state).

I want a really good interface for dealing with merge conflicts built in. I'm thinking it would have its own dedicated window.

The app should remember what windows/repos are open, and all their positions, so that the app can be quit, and when open it resume where the user left off.

If no windows are open, it should have a dashboard area that lists all the projects that have been opened before, with a search, and an option to open one from the filesystem. It should also offer to clone/create from remote. The dashboard should always be invokable with a keyboard shortcut (or menu item) and the search field should always be focused by default when opening the dashboard. The dashboard is transient, after a repo is opened from the dashboard, it closes.

Speaking of menu items, good Mac apps LOVE the menu and menu items, we should use the menu copiously for any action that can be taken. And we should assign good keyboard shortcuts as we can.

Windows should be able to have tabs.

I've built two other, smaller Mac-only apps, Locus Launcher (/Volumes/Promenade/git/locus-launcher) and Locus Sound Control (/Volumes/Promenade/git/locus-sound-control). And I've built one cross-platform Apple app, Locus ToDo (/Volumes/Promenade/git/locus-todo). That should help you get a sense of my style and what I like. If there's any family resemblance we can give this app, we should. Unlike my other two Mac-only apps, this one will have a standard window interface, of course, where the other two are menu bar apps. Also look at the High Level Plans in the Mac apps.

Let's create a high level plan with slices of work that we can bite off.