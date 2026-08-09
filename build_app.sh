#!/bin/zsh
# Package MacShapearator.app with its Python engine, interpreter, and tools.
#
# Every external location is discovered or overridable by environment variable
# so this runs on any Mac, not just the author's:
#
#   SHAPEARATOR_SRC   path to a Shapearator checkout   (default: ../shapearator)
#   SHAPEARATOR_REF   git ref of the engine to ship    (default: $MINIMUM_ENGINE)
#   PYTHON_SRC        interpreter root to bundle       (default: python3 on PATH)
#   INKSCAPE_APP      Inkscape.app to bundle           (default: /Applications)
#   POTRACE_PREFIX    Homebrew potrace prefix          (default: brew --prefix)
set -euo pipefail

cd "$(dirname "$0")"

# Keep in step with MINIMUM_ENGINE_VERSION in Sources/MacShapearator/AppRuntime.swift.
MINIMUM_ENGINE="v0.4.1"

SHAPEARATOR_SRC="${SHAPEARATOR_SRC:-../shapearator}"
SHAPEARATOR_REF="${SHAPEARATOR_REF:-$MINIMUM_ENGINE}"
INKSCAPE_APP="${INKSCAPE_APP:-/Applications/Inkscape.app}"

die() { print -u2 "error: $*"; exit 1; }

# --- Python interpreter ----------------------------------------------------
if [[ -z "${PYTHON_SRC:-}" ]]; then
  python_bin="$(command -v python3 || true)"
  [[ -n "$python_bin" ]] || die "No python3 on PATH. Set PYTHON_SRC to an interpreter root."
  PYTHON_SRC="$("$python_bin" -c 'import sys; print(sys.prefix)')"
fi
[[ -x "$PYTHON_SRC/bin/python3" ]] || die "No interpreter at $PYTHON_SRC/bin/python3"

# --- potrace ---------------------------------------------------------------
if [[ -z "${POTRACE_PREFIX:-}" ]]; then
  POTRACE_PREFIX="$(brew --prefix potrace 2>/dev/null || true)"
fi
[[ -n "$POTRACE_PREFIX" && -x "$POTRACE_PREFIX/bin/potrace" ]] \
  || die "potrace not found. Install it (brew install potrace) or set POTRACE_PREFIX."

# --- Engine ----------------------------------------------------------------
# The engine is a build artifact, never a checked-in copy: a hand-made copy is
# how the shipped app silently drifted onto a months-old, buggy engine.
[[ -d "$SHAPEARATOR_SRC/.git" ]] \
  || die "No Shapearator checkout at $SHAPEARATOR_SRC. Set SHAPEARATOR_SRC."
git -C "$SHAPEARATOR_SRC" rev-parse --verify --quiet "$SHAPEARATOR_REF" >/dev/null \
  || die "Ref '$SHAPEARATOR_REF' not found in $SHAPEARATOR_SRC. Fetch it, or set SHAPEARATOR_REF."

print "Bundling engine $SHAPEARATOR_REF from $SHAPEARATOR_SRC"
rm -rf Resources/BundledBackend
mkdir -p Resources/BundledBackend
git -C "$SHAPEARATOR_SRC" archive "$SHAPEARATOR_REF" services requirements.txt \
  | tar -x -C Resources/BundledBackend
print "$SHAPEARATOR_REF" > Resources/BundledBackend/ENGINE_VERSION

# --- Bridge scripts --------------------------------------------------------
# Single source of truth is Scripts/; Resources/ is a packaging copy.
mkdir -p Resources/Scripts
cp Scripts/extract_bridge.py Scripts/engine_bridge.py Resources/Scripts/

# --- Interpreter, Inkscape, potrace ---------------------------------------
rm -rf Resources/BundledPython Resources/BundledBin Resources/ThirdParty
mkdir -p Resources/BundledPython Resources/BundledBin Resources/ThirdParty

print "Bundling interpreter from $PYTHON_SRC"
rsync -a "$PYTHON_SRC/" Resources/BundledPython/python/

if [[ -d "$INKSCAPE_APP" ]]; then
  print "Bundling $INKSCAPE_APP"
  rsync -a "$INKSCAPE_APP/" Resources/ThirdParty/Inkscape.app/
else
  print -u2 "warning: $INKSCAPE_APP not found; SVG input will not work in the packaged app."
fi

cp "$POTRACE_PREFIX/bin/potrace" Resources/BundledBin/potrace
cp "$POTRACE_PREFIX/lib/libpotrace.0.dylib" Resources/BundledBin/libpotrace.0.dylib
chmod +x Resources/BundledBin/potrace
install_name_tool -change \
  "$POTRACE_PREFIX/lib/libpotrace.0.dylib" \
  "@executable_path/libpotrace.0.dylib" \
  Resources/BundledBin/potrace

# --- Build -----------------------------------------------------------------
xcodegen generate
xcodebuild \
  -project MacShapearator.xcodeproj \
  -scheme MacShapearator \
  -configuration Debug \
  -derivedDataPath build \
  build

print "Built app: $(pwd)/build/Build/Products/Debug/MacShapearator.app"
print "Bundled engine: $SHAPEARATOR_REF"
