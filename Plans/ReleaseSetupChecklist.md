# Release Setup Checklist

Work through this once before the first release. Keep it afterwards as the record of what was set up and where, and as the list to work through again if it ever has to be rebuilt on another machine.

`Scripts/release.sh <version>` handles every release from here.

Background and commands for each step are in [`Scripts/README.md`](../Scripts/README.md).

## Signing

- [x] Confirm the **Developer ID Application** certificate is present: `security find-identity -v -p codesigning` lists `Developer ID Application: … (CQZ49H6WAK)`. It is per team, so the one the other Locus apps use covers this app too.
- [x] Open the project in Xcode and build once, so it registers `com.buzzingpixel.LocusGitGui` with the iCloud capability and creates a development profile. Signing & Capabilities should show iCloud with Key-value storage and no errors.
- [x] Create a **Developer ID provisioning profile** by archiving once in Xcode: Product → Archive, then Distribute App → Direct Distribution. The app already carries the iCloud key-value storage entitlement the license needs, and a Developer ID build can only carry it with a profile. `xcodebuild` cannot create one from the command line.

## Notarization

An App Store Connect API key covers the whole team, so this uses the same key as the other Locus apps, stored under this app's profile name.

- [x] Save the key's `.p8` to disk temporarily, and note its Key ID and Issuer ID.
- [x] Store the credentials in the Keychain under the name the script expects:
      ```
      xcrun notarytool store-credentials "LocusGitGui" \
        --key ~/Downloads/AuthKey_XXXXXXXX.p8 \
        --key-id XXXXXXXX \
        --issuer <issuer-uuid>
      ```
- [x] Confirm it works: `xcrun notarytool history --keychain-profile "LocusGitGui"`.
- [x] Delete the `.p8` from disk.

## Sparkle signing key

This app shares the Locus apps' key. Sparkle's own guidance is one key per publisher, not per app, and `generate_keys` reuses the existing one anyway unless told to use a different `--account`.

- [x] Print the public half: `Scripts/sparkle-tools.sh generate_keys -p`.
- [x] Confirm it matches `SUPublicEDKey` in `LocusGitGui/SupportingFiles/Info.plist`. **Nothing can update unless it does**, and it has to be in the build before the first release ships.
- [x] Nothing to back up — the private half is the one already saved during Locus Launcher's setup.

## Hosting

- [x] The repo is public at `tjdraper/locus-git-gui`.
- [ ] Enable GitHub Pages: repo Settings → Pages → Source **Deploy from a branch**, branch `main`, folder `/docs`.
- [ ] Commit and push `docs/` so Pages has something to serve. The seeded `appcast.xml` is an empty channel, which is what Sparkle should see before the first release.
- [ ] Confirm `https://tjdraper.github.io/locus-git-gui/appcast.xml` loads. That URL is the `SUFeedURL` baked into every build, so it has to work before the first release ships.
- [ ] Run the app and pick **Check for Updates…**. Against the empty feed it should say you are up to date. An error here means the feed URL is wrong, and it is much cheaper to find out now.

## Contributor license agreement

- [ ] Create the branch the signatures are stored on, since the action won't create it: `git push origin main:cla-signatures`.
- [ ] Confirm the **CLA Assistant** workflow runs: open a throwaway pull request from another account or a fork, check it fails the CLA check, sign with the comment, and check it passes. The workflow uses the built-in `GITHUB_TOKEN`, so there is no secret to add while signatures are stored in this repository.

## First release

- [ ] `Scripts/release.sh 2026.0.1`
- [ ] Run the commands it prints, in the order it prints them.
- [ ] Download the published zip on a Mac that has never run the app, unzip it in Downloads, and open it. You should get no Gatekeeper warning, and the offer to move it to Applications.
- [ ] Ship a throwaway `2026.0.2` and let an installed `2026.0.1` update itself. Sparkle problems only show up on the second release, so do this before anyone else is relying on it.

## Not set up on purpose

- **Release notes** are required. Write `docs/LocusGitGui-<version>.md` before running the script. That one file becomes the Sparkle update description and the GitHub release body.
- **Publishing** is not automated. The script stops with the artifacts built and prints the `gh release create` and `git` commands, so nothing goes public without you running it.
- **The beta channel** works, but has no UI yet. Opt in with `defaults write com.buzzingpixel.LocusGitGui ReceiveBetaUpdates -bool YES`; the Settings toggle comes with Settings. A build that is itself a beta receives the next beta without opting in.
