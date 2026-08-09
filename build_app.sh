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
