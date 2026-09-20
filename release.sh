#!/bin/zsh
# Sign, notarize, and package MacShapearator for distribution.
#
# Run ./build_app.sh first. This script never handles your credentials: signing
# uses an identity already in your keychain, and notarization uses a keychain
# profile you create once with
#
#   xcrun notarytool store-credentials MacShapearator \
#       --apple-id you@example.com --team-id TEAMID
#
# (that command prompts for an app-specific password and stores it in the
# keychain; nothing is passed on this script's command line or written to disk).
#
#   SIGN_IDENTITY     "Developer ID Application: Name (TEAMID)"
#                     Default: the first Developer ID Application identity found.
#   NOTARY_PROFILE    notarytool keychain profile name. Default: MacShapearator
#   BUILD_CONFIG      Build configuration to package. Default: Release
#   APP_PATH          .app to package. Default: the $BUILD_CONFIG build product.
#   SKIP_NOTARIZE=1   Sign and package without submitting to Apple.
set -euo pipefail

cd "$(dirname "$0")"

# build_app.sh builds Release by default; a Debug product is a preview shim
# plus __preview.dylib, which notarization rejects. Keep the two in step.
BUILD_CONFIG="${BUILD_CONFIG:-Release}"
APP_PATH="${APP_PATH:-$(pwd)/build/Build/Products/$BUILD_CONFIG/MacShapearator.app}"
NOTARY_PROFILE="${NOTARY_PROFILE:-MacShapearator}"
DIST_DIR="${DIST_DIR:-$(pwd)/dist}"
ENTITLEMENTS="$(pwd)/Resources/MacShapearator.entitlements"

die() { print -u2 "error: $*"; exit 1 }

[[ -d "$APP_PATH" ]] || die "No app at $APP_PATH. Run ./build_app.sh first."

# --- Identity --------------------------------------------------------------
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)"/\1/')"
fi
[[ -n "$SIGN_IDENTITY" ]] || die \
  "No Developer ID Application identity found in your keychain.
   Signing and notarization need an Apple Developer account.
   Set SIGN_IDENTITY explicitly, or run with SKIP_NOTARIZE=1 after adding one."

print "Signing with: $SIGN_IDENTITY"

# --- Entitlements ----------------------------------------------------------
# The app spawns a Python interpreter and Inkscape, so the hardened runtime
# must allow loading unsigned-at-build-time libraries and JIT-free execution of
# our own bundled tools.
if [[ ! -f "$ENTITLEMENTS" ]]; then
  mkdir -p "$(dirname "$ENTITLEMENTS")"
  cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- The bundled interpreter and Inkscape are not signed by us at build time. -->
    <key>com.apple.security.cs.disable-library-validation</key><true/>
    <!-- Python writes and executes bytecode caches. -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
    <!-- The user picks input sheets and output folders anywhere on disk. -->
    <key>com.apple.security.files.user-selected.read-write</key><true/>
</dict>
</plist>
PLIST
  print "Wrote default entitlements to $ENTITLEMENTS"
fi

# --- Sign ------------------------------------------------------------------
# Nested code must be signed inside-out. --deep is unreliable for bundles that
# contain a whole app and an interpreter, so every Mach-O is signed explicitly.
# Every Mach-O in the bundle, one at a time. Containers come afterwards, in
# order: framework versions, then nested .app bundles, then the app itself.
# Signing a file inside a bundle does break that bundle's seal -- which is
# what the first notarization failed on -- but the answer is to re-seal the
# container afterwards, not to leave its contents unsigned.
print "Signing bundled binaries (this takes a minute on a bundle this size)…"
failed=0
while IFS= read -r -d '' binary; do
  # Everything, including code inside nested bundles. Excluding those left
  # 475 unsigned .so files inside Inkscape's framework: sealing a bundle
  # covers its resources, but the notary service still wants each Mach-O
  # signed. Inside-out is the rule -- files first, containers after.
  [[ "$(file -b "$binary")" == *Mach-O* ]] || continue
  # No `|| true` here. A binary that cannot be signed is a binary the notary
  # service will reject, and swallowing that is how the failure stayed hidden.
  if ! codesign --force --timestamp --options runtime \
       --sign "$SIGN_IDENTITY" "$binary" >/dev/null 2>&1; then
    print -u2 "  could not sign: ${binary#$APP_PATH/}"
    failed=$(( failed + 1 ))
  fi
done < <(find "$APP_PATH/Contents/Resources" \
  \( -type f \( -perm -u+x -o -name '*.dylib' -o -name '*.so' \) \) -print0 2>/dev/null)
(( failed == 0 )) || die "$failed bundled binaries could not be signed."

# A framework is signed by its version directory, as a unit. Signing the bare
# Mach-O inside leaves the framework reporting "a sealed resource is missing
# or invalid", which passes codesign --verify on the file and fails the notary
# service on the bundle.
#
# No depth limit. Inkscape's embedded Python framework sits seven levels down
# and an earlier -maxdepth 6 matched nothing at all, silently, so the notary
# service found the ad-hoc signature instead.
while IFS= read -r -d '' framework; do
  for version in "$framework"/Versions/*(N); do
    [[ -L "$version" || ! -d "$version" ]] && continue   # Versions/Current is a symlink
    print "  signing framework: ${version#$APP_PATH/Contents/Resources/}"
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$version"
  done
done < <(find "$APP_PATH/Contents/Resources" -type d -name '*.framework' -print0 2>/dev/null)

# Nested .app bundles are signed as units, after their contents.
while IFS= read -r -d '' nested; do
  print "  signing nested bundle: $(basename "$nested")"
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$nested"
done < <(find "$APP_PATH/Contents/Resources" -name '*.app' -maxdepth 3 -print0 2>/dev/null)

print "Signing the app bundle…"
codesign --force --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH" \
  || die "Signature verification failed."
print "Signature verified."

# What the notary service checks, checked here first. Three submissions were
# spent learning about ad-hoc signatures Apple found and this script did not,
# each one a five-minute round trip after a full sign and package.
print "Verifying every bundled binary carries a Developer ID signature…"
adhoc=0
while IFS= read -r -d '' binary; do
  # No pipelines here. Under `set -o pipefail`, `codesign -dvv | grep -q`
  # reports failure whenever grep matches early: grep exits, codesign takes
  # SIGPIPE mid-write, and the pipeline's status is codesign's. Every signed
  # binary was counted as unsigned, and the release stopped on 475 files that
  # were all correctly signed.
  [[ "$(file -b "$binary")" == *Mach-O* ]] || continue
  description="$(codesign -dvv "$binary" 2>&1)"
  if [[ "$description" != *"Authority=Developer ID Application"* ]]; then
    print -u2 "  not Developer ID signed: ${binary#$APP_PATH/}"
    adhoc=$(( adhoc + 1 ))
  fi
done < <(find "$APP_PATH" \
  \( -type f \( -perm -u+x -o -name '*.dylib' -o -name '*.so' \) \) -print0 2>/dev/null)
(( adhoc == 0 )) \
  || die "$adhoc bundled binaries are not Developer ID signed; the notary service would reject them."
print "All bundled binaries are Developer ID signed."

# --- Package ---------------------------------------------------------------
mkdir -p "$DIST_DIR"
# The stamp is written as a git ref ("v0.4.2"); carry the tag spelling and a
# bare number separately so neither the filename nor the tag grows a second v.
ENGINE_REF="$(cat "$APP_PATH/Contents/Resources/BundledBackend/ENGINE_VERSION" 2>/dev/null || echo dev)"
# The disk image is named after the app, which is what the person downloading
# it sees in Finder and in About. It followed the engine version until the two
# diverged for a packaging-only fix, and then produced a 0.4.9 app inside a
# file called 0.4.8.
VERSION="$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null \
           || print -- "${ENGINE_REF#v}")"
# The ref is a git ref, and a branch name contains slashes. Unsanitised it
# turned the disk image into dist/MacShapearator-fix/label-.../....dmg and
# hdiutil failed on a directory that was never created.
SAFE_VERSION="${VERSION//\//-}"
DMG_PATH="$DIST_DIR/MacShapearator-${SAFE_VERSION}.dmg"
rm -f "$DMG_PATH"

STAGING="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
print "Building $DMG_PATH…"
hdiutil create -volname "MacShapearator" -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGING"
print "Disk image: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"

# --- Notarize --------------------------------------------------------------
if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  print "Skipping notarization (SKIP_NOTARIZE=1)."
  print "The disk image is signed but will warn on other Macs until notarized."
  exit 0
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  die "No notarytool profile '$NOTARY_PROFILE' in your keychain. Create one with:
   xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <you> --team-id <TEAMID>
   Or re-run with SKIP_NOTARIZE=1."
fi

print "Submitting to Apple for notarization (this can take several minutes)…"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait \
  || die "Notarization failed. Inspect the log with: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"

xcrun stapler staple "$DMG_PATH" || die "Could not staple the notarization ticket."
print "Notarized and stapled: $DMG_PATH"
print ""
print "Publish it as a release asset rather than committing it:"
print "  gh release create \"v$VERSION\" \"$DMG_PATH\" --repo tsevis/MacShapearator"
print "  (engine in this build: $ENGINE_REF)"
