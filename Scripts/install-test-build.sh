#!/usr/bin/env bash
#
# Builds a notarized copy of the working tree without releasing it, swaps it in for the copy in
# /Applications, and opens it. Several things only behave correctly in a real installed, signed
# build: privacy prompts, which macOS attributes to whatever launched the app, so a build run from
# Terminal or Xcode borrows their access; iCloud key-value storage; the Sparkle update flow;
# Gatekeeper; and the offer to move to Applications.
#
# Needs the same one-time setup as release.sh, apart from the Sparkle key (see Scripts/README.md).

set -euo pipefail

readonly PROJECT="Locus Git Gui.xcodeproj"
readonly SCHEME="Locus Git Gui"
readonly APP_NAME="Locus Git Gui"
readonly ARTIFACT_NAME="LocusGitGui"

readonly NOTARY_PROFILE="${LOCUS_GIT_GUI_NOTARY_PROFILE:-LocusGitGui}"

cd "$(dirname "${BASH_SOURCE[0]}")/.."
readonly REPO_ROOT="$PWD"
readonly WORK_DIR="$REPO_ROOT/build/test-build"
readonly ARCHIVE="$WORK_DIR/$ARTIFACT_NAME.xcarchive"
readonly EXPORT_DIR="$WORK_DIR/export"
readonly EXPORTED_APP="$EXPORT_DIR/$APP_NAME.app"
readonly ZIP="$WORK_DIR/$ARTIFACT_NAME.zip"
readonly INSTALLED_APP="/Applications/$APP_NAME.app"
readonly INSTALLED_BINARY="$INSTALLED_APP/Contents/MacOS/$APP_NAME"

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo
    echo "==> $*"
}

step "Checking prerequisites"

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
    || fail "no Developer ID Application certificate in the keychain (see Scripts/README.md)"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null 2>&1 \
    || fail "notarytool profile '$NOTARY_PROFILE' is missing or invalid (see Scripts/README.md)"

# Checked here rather than where it is used, because that is on the far side of notarization.
command -v trash >/dev/null \
    || fail "the 'trash' command is missing; install it with 'brew install trash'"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

step "Archiving"
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

step "Notarizing (this waits for Apple)"
# Plain `zip` drops the symlinks and extended attributes that a signed bundle needs.
ditto -c -k --keepParent "$EXPORTED_APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

step "Stapling"
xcrun stapler staple "$EXPORTED_APP"
spctl --assess --type exec --verbose=2 "$EXPORTED_APP"

step "Quitting the installed copy"
# Matched by path so a Debug copy running from Xcode, which has the same bundle ID, is left alone.
if pkill -TERM -f "^$INSTALLED_BINARY"; then
    for _ in {1..50}; do
        pgrep -f "^$INSTALLED_BINARY" >/dev/null || break
        sleep 0.1
    done
    pgrep -f "^$INSTALLED_BINARY" >/dev/null && fail "the installed copy did not quit"
fi

step "Replacing $INSTALLED_APP"
[[ -e "$INSTALLED_APP" ]] && trash "$INSTALLED_APP"
ditto "$EXPORTED_APP" "$INSTALLED_APP"

step "Opening"
open "$INSTALLED_APP"

echo
echo "Installed and opened a notarized build of the working tree."
