#!/usr/bin/env bash
#
# Builds, signs, notarizes and staples a release, then adds it to the Sparkle appcast.
# Publishing is left to you: the script prints the two commands at the end.
#
# One-time setup is documented in Scripts/README.md.

set -euo pipefail

readonly PROJECT="Locus Git Gui.xcodeproj"
readonly SCHEME="Locus Git Gui"
readonly APP_NAME="Locus Git Gui"
readonly ARTIFACT_NAME="LocusGitGui"
readonly GITHUB_REPO="tjdraper/locus-git-gui"

readonly NOTARY_PROFILE="${LOCUS_GIT_GUI_NOTARY_PROFILE:-LocusGitGui}"

cd "$(dirname "${BASH_SOURCE[0]}")/.."
readonly REPO_ROOT="$PWD"
readonly PBXPROJ="$PROJECT/project.pbxproj"
readonly BUILD_DIR="$REPO_ROOT/build"
readonly APPCAST="$REPO_ROOT/docs/appcast.xml"

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo
    echo "==> $*"
}

# --- Arguments -------------------------------------------------------------

readonly VERSION="${1:-}"
[[ -n "$VERSION" ]] \
    || fail "usage: Scripts/release.sh <version>   (2026.4 for a release, 2026.3.1 for a beta)"

# The shape of the version picks the channel, so the two can never disagree. Betas leading to
# YYYY.N are numbered YYYY.(N-1).B, which keeps them below that release and above the one before.
if [[ "$VERSION" =~ ^[0-9]{4}\.[0-9]+$ ]]; then
    readonly CHANNEL=""
elif [[ "$VERSION" =~ ^[0-9]{4}\.[0-9]+\.[0-9]+$ ]]; then
    readonly CHANNEL="beta"
else
    fail "version must be YYYY.N for a release or YYYY.N.B for a beta, got '$VERSION'"
fi

# Written by hand, and published as-is: Sparkle fetches it from the same place as the appcast.
readonly RELEASE_NOTES="$REPO_ROOT/docs/$ARTIFACT_NAME-$VERSION.md"
readonly RELEASE_NOTES_PATH="docs/$ARTIFACT_NAME-$VERSION.md"

# --- Preflight -------------------------------------------------------------

step "Checking prerequisites"

# This version's notes are allowed to be uncommitted, since they go in with the release commit.
[[ -z "$(git status --porcelain -uall | grep -v "^?? $RELEASE_NOTES_PATH\$")" ]] \
    || fail "working tree is dirty; commit or stash first"

readonly BRANCH="$(git rev-parse --abbrev-ref HEAD)"
UPSTREAM="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" \
    || fail "$BRANCH has no upstream branch, so there is nothing to tag against"
readonly UPSTREAM

git fetch --quiet --tags

# The build number is the version, so a released version can never be rebuilt under the same name.
git rev-parse --verify --quiet "refs/tags/v$VERSION" >/dev/null \
    && fail "v$VERSION is already tagged; pick a new version"

# The tag has to land on the commit this build came from, so nothing else may be unpushed.
[[ "$(git rev-list --count "$UPSTREAM..HEAD")" == "0" ]] \
    || fail "$BRANCH is ahead of $UPSTREAM; push before releasing"
[[ "$(git rev-list --count "HEAD..$UPSTREAM")" == "0" ]] \
    || fail "$BRANCH is behind $UPSTREAM; pull before releasing"

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
    || fail "no Developer ID Application certificate in the keychain (see Scripts/README.md)"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null 2>&1 \
    || fail "notarytool profile '$NOTARY_PROFILE' is missing or invalid (see Scripts/README.md)"

# --- Sparkle tools ---------------------------------------------------------

readonly SPARKLE_BIN="$("$REPO_ROOT/Scripts/sparkle-tools.sh")"

"$SPARKLE_BIN/generate_keys" -p >/dev/null 2>&1 \
    || fail "no Sparkle EdDSA signing key in the keychain (see Scripts/README.md)"

# --- Release notes ---------------------------------------------------------
#
# Last, so that a run which stops here has already confirmed everything else is in order.

if [[ ! -f "$RELEASE_NOTES" ]]; then
    : > "$RELEASE_NOTES"
    cat <<EOF

Everything else is ready, but $VERSION has no release notes.

Created the notes file below. Write them there and run this again. Sparkle renders Markdown in
its update dialog: headings, lists, code blocks, blockquotes and tables.

$RELEASE_NOTES

EOF
    exit 1
fi

[[ -n "$(tr -d '[:space:]' < "$RELEASE_NOTES")" ]] \
    || fail "the release notes are empty; write them before releasing: $RELEASE_NOTES"

# --- Version ---------------------------------------------------------------

step "Setting version $VERSION"
# CFBundleVersion is what Sparkle compares. Keeping it equal to the marketing version leaves one
# number to reason about, at the cost of needing a new version to rebuild a released one.
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $VERSION;/g" "$PBXPROJ"

# --- Archive and export ----------------------------------------------------

readonly ARCHIVE="$BUILD_DIR/$ARTIFACT_NAME-$VERSION.xcarchive"
readonly EXPORT_DIR="$BUILD_DIR/export-$VERSION"
readonly EXPORTED_APP="$EXPORT_DIR/$APP_NAME.app"

step "Archiving"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates

step "Exporting a Developer ID build"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$REPO_ROOT/Scripts/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates

step "Verifying the signature"
codesign --verify --deep --strict --verbose=2 "$EXPORTED_APP"
signature="$(codesign --display --verbose=2 "$EXPORTED_APP" 2>&1)"
grep -q "flags=.*runtime" <<<"$signature" \
    || fail "the exported app is not signed with the hardened runtime"
grep -q "Developer ID Application" <<<"$signature" \
    || fail "the exported app is not signed with a Developer ID Application certificate"

# --- Notarize --------------------------------------------------------------

readonly STAGE_DIR="$BUILD_DIR/appcast-$VERSION"
readonly ZIP="$STAGE_DIR/$ARTIFACT_NAME-$VERSION.zip"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

step "Zipping for notarization"
# Plain `zip` drops the symlinks and extended attributes that a signed bundle needs.
ditto -c -k --keepParent "$EXPORTED_APP" "$ZIP"

step "Notarizing (this waits for Apple)"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

step "Stapling"
xcrun stapler staple "$EXPORTED_APP"
xcrun stapler validate "$EXPORTED_APP"

step "Checking Gatekeeper"
spctl --assess --type exec --verbose=2 "$EXPORTED_APP"

step "Re-zipping the stapled app"
# The ticket has to be inside the archive users download, so the zip is rebuilt after stapling.
rm -f "$ZIP"
ditto -c -k --keepParent "$EXPORTED_APP" "$ZIP"

# --- Appcast ---------------------------------------------------------------

step "Updating the appcast"
cp "$APPCAST" "$STAGE_DIR/appcast.xml"
# generate_appcast pairs notes with an archive by filename, which is why both are named alike.
cp "$RELEASE_NOTES" "$STAGE_DIR/$ARTIFACT_NAME-$VERSION.md"

# Items with no channel are the default one, which every updater sees. A beta item is only
# offered to updaters that ask for the channel by name.
# The +"..." guard is for bash 3.2, which macOS still ships: it treats an empty array as unset
# under `set -u` and would abort on a plain "${channel_args[@]}".
channel_args=()
[[ -n "$CHANNEL" ]] && channel_args=(--channel "$CHANNEL")

"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/v$VERSION/" \
    --link "https://github.com/$GITHUB_REPO" \
    ${channel_args[@]+"${channel_args[@]}"} \
    -o "$STAGE_DIR/appcast.xml" \
    "$STAGE_DIR"

cp "$STAGE_DIR/appcast.xml" "$APPCAST"

# --- Next steps ------------------------------------------------------------

cat <<EOF

Built and notarized $APP_NAME $VERSION$( [[ -n "$CHANNEL" ]] && echo " on the $CHANNEL channel" ).

  app: $EXPORTED_APP
  zip: $ZIP

Publish in this order. The tag lands on the release commit, and the download goes live before
the feed points at it:

  git add "$PBXPROJ" docs && git commit -m "Release $VERSION"
  git tag v$VERSION
  git push origin v$VERSION
  gh release create v$VERSION "$ZIP" --repo $GITHUB_REPO --title "$VERSION" --verify-tag --notes-file $RELEASE_NOTES_PATH$( [[ -n "$CHANNEL" ]] && echo " --prerelease" )
  git push

If you stop here, undo the version bump and the appcast entry with:

  git checkout -- "$PBXPROJ" docs
EOF
