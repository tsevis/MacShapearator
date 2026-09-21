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

# The oldest engine this app can talk to -- keep in step with
# minimumEngineVersion in Sources/MacShapearator/AppRuntime.swift.
MINIMUM_ENGINE="v0.4.11"
# The engine actually shipped: the newest release tested against this app.
# Deliberately not the minimum, or every build would ship the oldest engine
# still supported rather than the current one.
DEFAULT_ENGINE="v0.4.11"

# Stands in for the build machine's interpreter prefix inside the bundle's
# own metadata; nothing resolves it at runtime.
BUNDLE_PATH_PLACEHOLDER="/opt/macshapearator/python"

SHAPEARATOR_SRC="${SHAPEARATOR_SRC:-../shapearator}"
SHAPEARATOR_REF="${SHAPEARATOR_REF:-$DEFAULT_ENGINE}"
INKSCAPE_APP="${INKSCAPE_APP:-/Applications/Inkscape.app}"

die() { print -u2 "error: $*"; exit 1; }

# --- Python interpreter ----------------------------------------------------
# Not simply `python3` on PATH: that is often a Conda base (20 GB here) or the
# Xcode system stub, neither of which is a sane thing to relocate into an app.
# Prefer a self-contained pyenv or Homebrew interpreter.
suitable_interpreter() {
  local prefix="$1"
  [[ -x "$prefix/bin/python3" ]] || return 1
  [[ -d "$prefix/conda-meta" ]] && return 1                 # Conda: not relocatable
  [[ "$prefix" == /Applications/Xcode.app/* ]] && return 1  # system stub
  [[ "$prefix" == /System/* ]] && return 1
  return 0
}

if [[ -z "${PYTHON_SRC:-}" ]]; then
  # (N) is zsh's null-glob qualifier: a pattern that matches nothing expands to
  # nothing instead of aborting the script under `set -e`.
  for candidate in \
    "$HOME"/.pyenv/versions/3.1[0-9]*(N) \
    /opt/homebrew/opt/python@3.1[0-9]/Frameworks/Python.framework/Versions/3.1*(N) \
    /Library/Frameworks/Python.framework/Versions/3.1*(N)
  do
    if suitable_interpreter "$candidate"; then PYTHON_SRC="$candidate"; break; fi
  done
fi
[[ -n "${PYTHON_SRC:-}" ]] || die \
  "No suitable Python found to bundle. Set PYTHON_SRC to a self-contained
   interpreter prefix (a pyenv version or a python.org framework build).
   Conda prefixes and the Xcode system Python cannot be relocated into an app."
suitable_interpreter "$PYTHON_SRC" \
  || die "$PYTHON_SRC is not a self-contained interpreter prefix suitable for bundling."
print "Interpreter source: $PYTHON_SRC ($("$PYTHON_SRC/bin/python3" -V 2>&1))"

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

# The app refuses to run an engine older than MINIMUM_ENGINE. Finding that out
# at launch, after a 758 MB build, is finding out too late.
shipped_engine_version() {
  local stamp="Resources/BundledBackend/ENGINE_VERSION"
  local text="$(<"$stamp")"
  if [[ "$text" == (v|)<->.<->* ]]; then
    print -- "${text#v}"
    return
  fi
  # A branch or sha was pinned; fall back to the engine's own constant, the
  # same way AppRuntime.engineVersion does.
  sed -nE 's/^APP_VERSION[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' \
    Resources/BundledBackend/services/extractor.py | head -1
}
ENGINE_VERSION="$(shipped_engine_version)"
[[ -n "$ENGINE_VERSION" ]] \
  || die "Could not determine the version of the engine at $SHAPEARATOR_REF."
if [[ "$(printf '%s\n%s\n' "$ENGINE_VERSION" "${MINIMUM_ENGINE#v}" | sort -V | head -1)" \
      != "${MINIMUM_ENGINE#v}" ]]; then
  die "Engine $ENGINE_VERSION is older than the minimum this app supports ($MINIMUM_ENGINE)."
fi
print "Engine version: $ENGINE_VERSION (minimum $MINIMUM_ENGINE)"

# --- Bridge scripts --------------------------------------------------------
# Single source of truth is Scripts/; Resources/ is a packaging copy.
mkdir -p Resources/Scripts
cp Scripts/extract_bridge.py Scripts/engine_bridge.py Resources/Scripts/

# --- Interpreter, Inkscape, potrace ---------------------------------------
rm -rf Resources/BundledPython Resources/BundledBin Resources/ThirdParty
mkdir -p Resources/BundledPython Resources/BundledBin Resources/ThirdParty

# Copy the interpreter *without* its site-packages, then install only what the
# engine needs. Rsyncing a development interpreter wholesale is how the bundle
# reached 4.5 GB: it carried TensorFlow, PyTorch, JAX and friends, none of which
# Shapearator imports.
print "Bundling interpreter from $PYTHON_SRC (core only)"
PY_LIB="$(basename "$(dirname "$(find "$PYTHON_SRC/lib" -maxdepth 2 -name site-packages -type d | head -1)")")"
[[ -n "$PY_LIB" ]] || die "Could not locate site-packages under $PYTHON_SRC/lib"

rsync -a \
  --exclude "lib/$PY_LIB/site-packages/***" \
  --exclude "lib/$PY_LIB/test/***" \
  --exclude "lib/$PY_LIB/idlelib/***" \
  --exclude "lib/$PY_LIB/tkinter/***" \
  --exclude "lib/$PY_LIB/lib2to3/***" \
  --exclude "lib/$PY_LIB/ensurepip/***" \
  --exclude '**/__pycache__/***' --exclude '**/*.pyc' --exclude '**/*.pyo' \
  --exclude 'share/***' --exclude 'include/***' --exclude 'lib/pkgconfig/***' \
  --exclude 'lib/libpython*.a' \
  "$PYTHON_SRC/" Resources/BundledPython/python/

print "Installing engine requirements into the bundle"
# --no-warn-conflicts: pip otherwise reports clashes among packages installed in
# the *source* interpreter, which have nothing to do with this isolated --target
# install and make the build log look broken.
"$PYTHON_SRC/bin/python3" -m pip install \
  --quiet --no-cache-dir --no-compile --upgrade --no-warn-conflicts \
  --target "Resources/BundledPython/python/lib/$PY_LIB/site-packages" \
  -r Resources/BundledBackend/requirements.txt \
  || die "Could not install engine requirements into the bundle."

# Verify the slim runtime before it ships, rather than at a user's first launch.
PYTHONHOME="$(pwd)/Resources/BundledPython/python" PYTHONNOUSERSITE=1 \
  "Resources/BundledPython/python/bin/python3" \
  -c 'import cv2, numpy, PIL, requests, huggingface_hub' \
  || die "The bundled interpreter cannot import the engine's dependencies."
# The interpreter's bin/ carries the console scripts of every package the
# source interpreter had -- accelerate, argos-translate and 180 more. Their
# packages are gone (site-packages is excluded above), and each script's
# shebang is an absolute path on this build machine, so they are dead files
# that ship, and get signed and notarized, naming someone's home directory.
print "Pruning console scripts that point outside the bundle"
pruned=0
for script in \
  Resources/BundledPython/python/bin/*(N) \
  "Resources/BundledPython/python/lib/$PY_LIB/site-packages/bin"/*(N)
do
  [[ -f "$script" ]] || continue
  read -r shebang < "$script" 2>/dev/null || continue
  [[ "$shebang" == '#!'* ]] || continue
  [[ "$shebang" == *"/Resources/BundledPython/"* ]] && continue
  rm -f "$script"
  pruned=$(( pruned + 1 ))
done
print "Pruned $pruned console scripts"

# What is left naming this machine is the interpreter's own build metadata:
# sysconfigdata, the config Makefile, python-config. The runtime imports
# sysconfigdata, so these are rewritten rather than deleted -- the recorded
# paths only matter for compiling C extensions, which the app never does.
print "Scrubbing build-machine paths from interpreter metadata"
grep -rlI "$HOME" Resources/BundledPython 2>/dev/null | while IFS= read -r file; do
  LC_ALL=C sed -i '' \
    -e "s|$PYTHON_SRC|$BUNDLE_PATH_PLACEHOLDER|g" \
    -e "s|$HOME|$BUNDLE_PATH_PLACEHOLDER|g" "$file"
done

# Nothing in the bundle may name a path on this machine (definition of done #5).
# grep -I skips binaries, so this only covers text: the Mach-O load commands
# are checked by relocate_bundle.py above, which is where the real leak was.
if leaks=$(grep -rlI "$HOME" Resources/BundledPython Resources/BundledBin \
             Resources/Scripts Resources/BundledBackend 2>/dev/null); then
  print -u2 "error: bundled files name this machine's home directory:"
  print -u2 "$leaks"
  exit 1
fi

# Modules whose libraries we do not ship. Keeping the .so would drag in
# tcl/tk and gdbm purely to satisfy the relocation pass below; the engine
# imports none of them, and tkinter's package is already excluded above.
for orphan in _tkinter _dbm _gdbm; do
  rm -f "Resources/BundledPython/python/lib/$PY_LIB/lib-dynload/$orphan.cpython-"*"-darwin.so"(N)
done

print "Bundled interpreter: $(du -sh Resources/BundledPython | cut -f1)"

if [[ -d "$INKSCAPE_APP" ]]; then
  print "Bundling $INKSCAPE_APP"
  rsync -a "$INKSCAPE_APP/" Resources/ThirdParty/Inkscape.app/
  if [[ "${SLIM_INKSCAPE:-1}" == "1" ]]; then
    # Inkscape is used headlessly for --query-all and PNG export, so its
    # tutorials, translations and examples are dead weight. Removing them
    # invalidates Inkscape's own signature, which is why its _CodeSignature
    # goes too; release.sh re-signs every nested binary.
    for cruft in \
      Contents/Resources/share/inkscape/tutorials \
      Contents/Resources/share/inkscape/examples \
      Contents/Resources/share/inkscape/screens \
      Contents/Resources/share/locale \
      Contents/Resources/share/man \
      Contents/Resources/share/doc \
      Contents/_CodeSignature
    do
      rm -rf "Resources/ThirdParty/Inkscape.app/$cruft"
    done
    # Stripping invalidates Inkscape's signature. It still executes, but leaving
    # a bundle in a signature-mismatched state breaks notarization later, so
    # re-sign ad-hoc now; release.sh replaces this with a Developer ID signature.
    codesign --force --deep --sign - Resources/ThirdParty/Inkscape.app >/dev/null 2>&1 \
      || print -u2 "warning: could not ad-hoc re-sign the bundled Inkscape."
    print "Slimmed Inkscape: $(du -sh Resources/ThirdParty/Inkscape.app | cut -f1)"
  fi
  # Confirm the bundled copy still answers the calls the engine makes.
  if ! "Resources/ThirdParty/Inkscape.app/Contents/MacOS/inkscape" --version >/dev/null 2>&1; then
    die "The bundled Inkscape does not run. SVG input would fail in the packaged app."
  fi
else
  print -u2 "warning: $INKSCAPE_APP not found; SVG input will not work in the packaged app."
fi

cp "$POTRACE_PREFIX/bin/potrace" Resources/BundledBin/potrace
cp "$POTRACE_PREFIX/lib/libpotrace.0.dylib" Resources/BundledBin/libpotrace.0.dylib
chmod +x Resources/BundledBin/potrace
# No hand-rolled install_name_tool here any more: it changed
# "$POTRACE_PREFIX/lib/libpotrace.0.dylib" while the binary actually records
# the Cellar path it was linked against, so it silently matched nothing.
# relocate_bundle.py rewrites whatever is really there.

# Copying an interpreter does not move it: its load commands still name the
# paths it was linked against here. Until this ran, the bundled python3.10
# pointed at $HOME/.pyenv, _ssl at Homebrew's OpenSSL and potrace at a Cellar
# path -- so the app worked on this Mac and could not start its engine on any
# other. Must happen before signing; install_name_tool invalidates signatures.
print "Relocating bundled binaries into the app"
"$PYTHON_SRC/bin/python3" Scripts/relocate_bundle.py Resources \
  || die "Could not make the bundled binaries self-contained."

# --- Build -----------------------------------------------------------------
# Release by default. A Debug build makes the main executable a thin shim that
# loads the real code from MacShapearator.debug.dylib, and ships __preview.dylib
# alongside it — Xcode's SwiftUI preview scaffolding. Both end up inside the
# distributed disk image, and both have to be Developer ID signed for
# notarization to pass. Release produces a single ordinary executable instead.
# Pass "Debug" as the first argument when working on previews locally.
CONFIG="${1:-Release}"

xcodegen generate
xcodebuild \
  -project MacShapearator.xcodeproj \
  -scheme MacShapearator \
  -configuration "$CONFIG" \
  -derivedDataPath build \
  build

# Every Mach-O records the oldest macOS it loads on, and the bundled ones are
# not built here -- they carry whatever target pyenv and Homebrew used. If
# that is newer than the app promises, the app opens on a machine where its
# engine cannot start.
"$PYTHON_SRC/bin/python3" Scripts/check_minimum_os.py \
  "build/Build/Products/$CONFIG/MacShapearator.app" \
  || die "The app promises a macOS it cannot run on."

print "Built app: $(pwd)/build/Build/Products/$CONFIG/MacShapearator.app"
print "Bundled engine: $SHAPEARATOR_REF"
