# Releasing

```
Scripts/release.sh 2026.1
```

The script bumps the version, archives, exports a Developer ID build, notarizes it, staples the ticket, re-zips the stapled app, and adds the release to `docs/appcast.xml`. It does not publish: it prints the `gh release create` and `git` commands to run, in the order that keeps the download live before the feed points at it.

`CFBundleVersion` is set to the same value as the marketing version, so there is only one number to track. Sparkle compares `CFBundleVersion`, which means a version that has shipped can never be rebuilt under the same name — ship a new version instead. The script refuses a version you have already tagged.

Release notes are required. If `docs/LocusGitGui-<version>.md` is missing, the script checks everything else first, then creates the empty file and stops so you can write them. A blank or whitespace-only file fails the next run. Sparkle renders Markdown, so headings, lists, code blocks and tables work. Notes live in `docs/` because that is where Sparkle fetches them from, alongside the appcast. The script links the file from the appcast and passes it to `gh release create` as the GitHub release description. It does not need committing first; it goes in with the release commit.

The script refuses to run unless the branch is clean, has an upstream, and is exactly in sync with it. The release tag has to land on the commit the build came from, which is impossible if there is unpushed work in the way.

If a release fails partway, undo the version bump and the appcast entry with `git checkout -- "Locus Git Gui.xcodeproj/project.pbxproj" docs`.

## Testing a notarized build

```
Scripts/install-test-build.sh
```

Builds, notarizes, and staples the working tree as it is, without bumping the version or touching the appcast. It then quits the copy running from `/Applications`, moves that copy to the Trash, installs the new build in its place, and opens it. A Debug copy running from Xcode is left alone, because the running copy is matched by path rather than by bundle ID.

Use it for anything touching a permission, an entitlement, or how macOS registers the app. macOS attributes a privacy prompt to the process that launched the app, so a build started from Terminal or Xcode inherits their access and appears to work when an installed copy would be asked, or refused. That covers the prompts for repositories in Documents, Desktop, Downloads, and on external or network volumes; iCloud key-value storage; the URL scheme; folders dropped on the Dock icon; the Sparkle update flow; Gatekeeper; and the offer to move to Applications.

It needs `trash`, which is not part of macOS: `brew install trash`.

The build keeps whatever version the project currently has, so Sparkle may offer to replace it with a newer release.

## Large repositories for performance checks

Each slice whose work grows with a repository's size is tried against a large one before it's done (see Decisions in `Plans/HighLevelPlan.md`). Two kinds are worth having.

A generated repository, built in about a minute without the network:

```
swift Scripts/GenerateTestRepository.swift ~/Scratch/million --commits 1000000
```

It makes `main` and several lanes of work beside it (`--lanes`), each merged back into `main` in turn, plus extra branches (`--branches`), remote branches (`--remote-branches`) and tags (`--tags`). `--large-changes` ends `main` with commits whose diffs are hard to show, each tagged `perf/…`: 5,000 files changed at once (`perf/many-files`), a file of 200,000 lines with 20,000 of them changed (`perf/large-file`), a minified file whose one line is millions of characters (`perf/long-line`), and an 8000 × 6000 image (`perf/large-image`). The history's length doesn't change what they cost, so a short one will do:

```
swift Scripts/GenerateTestRepository.swift ~/Scratch/diffs --commits 2000 --large-changes
``` `--commit-graph` writes a commit-graph file afterwards; without it, the repository is in the state a fresh clone is usually in. Add or remove the file later with `git commit-graph write --reachable` and `rm .git/objects/info/commit-graph`. Run it with `--help` for the defaults.

A real one, for the shapes a generator doesn't make, such as octopus merges with dozens of parents. A blobless clone of the Linux kernel has its whole history, 1.3 million commits, without the file contents, which it fetches only when a diff needs them:

```
git clone --filter=blob:none https://github.com/torvalds/linux.git ~/Scratch/linux
```

The history's reading and graph layout can be timed against either without opening the app. The test suite skips these tests unless it's given a repository:

```
TEST_RUNNER_LOCUS_PERFORMANCE_REPOSITORY=~/Scratch/million xcodebuild -project "Locus Git Gui.xcodeproj" -scheme "Locus Git Gui" -destination "platform=macOS" test -only-testing:"Locus Git Gui Tests/HistoryPerformanceTests"
cat ~/Scratch/million-performance.txt
```

`DiffPerformanceTests` times reading and laying out the `perf/…` commits the same way, and skips any tag the repository doesn't have:

```
TEST_RUNNER_LOCUS_PERFORMANCE_REPOSITORY=~/Scratch/diffs xcodebuild -project "Locus Git Gui.xcodeproj" -scheme "Locus Git Gui" -destination "platform=macOS" -configuration Release test -only-testing:"Locus Git Gui Tests/DiffPerformanceTests"
```

The timings go in a file beside the repository, since a test's printed output doesn't reach `xcodebuild`. Each run adds to it.

In the app, the history logs how long each page took under the `History` category, and the diff how long a commit took to read (`CommitDetail`) and to lay out (`DiffView`) (see Reading the app's log in `AGENTS.md`).

## Versions and the beta channel

Versions are `YYYY.N` for a release and `YYYY.N.B` for a beta. Betas leading to `2026.4` are numbered `2026.3.1`, `2026.3.2` and so on: each sits above the `2026.3` release and below the `2026.4` it becomes. A year starts its betas at `YYYY.0.1` and its first release at `YYYY.1`.

```
2026.0.1    beta
2026.0.2    beta
2026.1      release
2026.1.1    beta
2026.2      release
```

The script reads the channel off the shape of the version, so the two cannot disagree. A three-part version is a beta: `generate_appcast` gets `--channel beta`, and the printed `gh release create` gets `--prerelease`.

Beta and release share one appcast. A beta item carries `<sparkle:channel>beta</sparkle:channel>`, which Sparkle only offers to updaters that ask for that channel by name, so everyone else sees releases only.

A Mac opts into betas through the `ReceiveBetaUpdates` default. There is no Settings toggle for it yet:

```
defaults write com.buzzingpixel.LocusGitGui ReceiveBetaUpdates -bool YES
```

The first launch of a full release on a Mac that was running a beta asks whether to keep getting betas.

A Mac already running a beta receives the next beta whether or not that default is set. Turning betas off from a beta build would strand it on that build until the next full release, with none of the fixes the betas in between carry.

A beta cannot be promoted in place, because `CFBundleVersion` is the version: `2026.1.2` ships again as `2026.2`, rebuilt and re-notarized.

## One-time setup

Work through [`Plans/ReleaseSetupChecklist.md`](../Plans/ReleaseSetupChecklist.md) once. The background for each step is below.

### Developer ID Application certificate

Xcode → Settings → Accounts → your Apple ID → Manage Certificates → **+** → Developer ID Application. Only the account holder can create one. If you already have one for another app, it covers this one too — the certificate is per team, not per app.

### Provisioning profiles

The license travels between Macs through iCloud key-value storage, and a Developer ID build can only carry that entitlement with a Developer ID provisioning profile. The entitlement is already in `LocusGitGui/SupportingFiles/LocusGitGui.entitlements`, so the profile is needed before the first release even though nothing reads iCloud yet — the point is to prove the release chain in the shape it will keep.

`xcodebuild` on the command line can't register the App ID or create profiles when it has no access to the Xcode account ("No Accounts"), so Xcode has to do both once:

- Open the project, select the Locus Git Gui target, and check Signing & Capabilities shows iCloud with Key-value storage and no errors. Building once from Xcode registers `com.buzzingpixel.LocusGitGui` and creates the development profile, which command line Debug builds need too.
- Product → Archive, then Distribute App → Direct Distribution. That creates the Developer ID profile. After that, the export in `release.sh` finds the profile Xcode keeps.

### Notarization credentials

An App Store Connect API key covers the whole team, so the key the other Locus apps notarize with works here too. Store it under this app's own profile name:

```
xcrun notarytool store-credentials "LocusGitGui" \
  --key ~/Downloads/AuthKey_XXXXXXXX.p8 \
  --key-id XXXXXXXX \
  --issuer <issuer-uuid>
```

The name must match the default in `release.sh`, or set `LOCUS_GIT_GUI_NOTARY_PROFILE` to whatever you used. If you don't have the `.p8` anymore, create a new key (App Store Connect → Users and Access → Integrations → Team Keys) with the Developer role. Delete the `.p8` from disk afterwards; the credentials live in the Keychain.

### Sparkle signing key

This app shares the Locus apps' key, which is what Sparkle recommends: the key identifies you as the publisher, not the app, and `generate_keys` reuses an existing one rather than making a second. `--account` exists for separating *organizations*, not apps.

```
Scripts/sparkle-tools.sh generate_keys -p
```

That prints the public half of the key already in the login Keychain. It must match `SUPublicEDKey` in `LocusGitGui/SupportingFiles/Info.plist`. Without a matching key, Sparkle has nothing to verify signatures against and refuses every update.

The private half is already backed up from Locus Launcher's setup, so there is nothing new to store. It stays the single point of failure for every Locus app: losing it means no installed copy of any of them can ever be updated again.

`sparkle-tools.sh` downloads Sparkle's command line tools into `build/tools/` if they aren't there yet, then runs the one you name. With no arguments it prints the directory holding them, which is how `release.sh` uses it. The version it downloads is pinned to the Sparkle version the app links, and the tarball is checked against a pinned SHA-256.

### GitHub Pages

Repo Settings → Pages → deploy from branch `main`, folder `/docs`. That serves the appcast at `https://tjdraper.github.io/locus-git-gui/appcast.xml`, which is the `SUFeedURL` baked into every build.

If the feed ever moves to a custom domain, add it to the same Pages site rather than changing `SUFeedURL`. GitHub redirects the old URL, so installs already in the wild keep updating.
