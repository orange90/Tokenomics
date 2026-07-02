#!/usr/bin/env bash
#
# release.sh — Build, archive, export and package Tokenomics.app
#
# Produces:
#   build/release/Tokenomics-<version>.zip
#   build/release/Tokenomics-<version>.dmg
#
# Usage:
#   ./scripts/release.sh                # version read from project.yml (MARKETING_VERSION)
#   ./scripts/release.sh 0.2.0          # override version
#   SKIP_CLEAN=1 ./scripts/release.sh   # keep previous build/ contents
#
# Requirements:
#   - Xcode 15+ (xcodebuild)
#   - XcodeGen (brew install xcodegen)
#   - hdiutil  (macOS built-in)
#   - ditto    (macOS built-in)
#
# Notarization is intentionally NOT performed. Users opening the app for
# the first time may need to right-click → Open to bypass Gatekeeper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SCHEME="Tokenomics"
PROJECT="Tokenomics.xcodeproj"
CONFIGURATION="Release"

BUILD_DIR="$REPO_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Tokenomics.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
RELEASE_DIR="$BUILD_DIR/release"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"

log()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
die()  { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

read_marketing_version() {
  /usr/bin/awk '
    /^settings:/                 { in_settings = 1; next }
    in_settings && /^[^[:space:]]/ { in_settings = 0 }
    in_settings && /MARKETING_VERSION:/ {
      gsub(/.*MARKETING_VERSION:[[:space:]]*/, "")
      gsub(/["'\'']/, "")
      gsub(/[[:space:]]+$/, "")
      print
      exit
    }
  ' "$REPO_ROOT/project.yml"
}

require_cmd xcodebuild
require_cmd xcodegen
require_cmd hdiutil
require_cmd ditto
require_cmd /usr/libexec/PlistBuddy

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(read_marketing_version || true)"
fi
[[ -n "$VERSION" ]] || die "cannot determine version (MARKETING_VERSION not found in project.yml)"

log "Version: $VERSION"

if [[ -z "${SKIP_CLEAN:-}" ]]; then
  log "Cleaning $BUILD_DIR"
  rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR" "$RELEASE_DIR"

log "Generating Xcode project (xcodegen)"
xcodegen generate --quiet

log "Archiving $SCHEME ($CONFIGURATION)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  | xcpretty 2>/dev/null || xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -destination "generic/platform=macOS" \
      -archivePath "$ARCHIVE_PATH" \
      archive

log "Writing export options"
cat > "$EXPORT_OPTIONS_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
PLIST

log "Exporting .app to $EXPORT_DIR"
rm -rf "$EXPORT_DIR"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

APP_PATH="$EXPORT_DIR/$SCHEME.app"
[[ -d "$APP_PATH" ]] || die "exported app not found at $APP_PATH"

log "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" || warn "codesign verify reported issues"

ZIP_PATH="$RELEASE_DIR/Tokenomics-$VERSION.zip"
DMG_PATH="$RELEASE_DIR/Tokenomics-$VERSION.dmg"

log "Packaging ZIP → $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

log "Packaging DMG → $DMG_PATH"
rm -f "$DMG_PATH"
DMG_STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
ditto "$APP_PATH" "$DMG_STAGE/$SCHEME.app"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create \
  -volname "Tokenomics $VERSION" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$DMG_STAGE"

log "Done"
printf "\n"
printf "  Version : %s\n" "$VERSION"
printf "  App     : %s\n" "$APP_PATH"
printf "  ZIP     : %s (%s)\n" "$ZIP_PATH" "$(du -h "$ZIP_PATH" | awk '{print $1}')"
printf "  DMG     : %s (%s)\n" "$DMG_PATH" "$(du -h "$DMG_PATH" | awk '{print $1}')"
printf "\nNote: the app is signed with 'Apple Development' and not notarized.\n"
printf "First-time users may need right-click → Open to bypass Gatekeeper.\n"
