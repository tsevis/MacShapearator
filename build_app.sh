#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

PYTHON_SRC="/Users/tsevis/.pyenv/versions/3.10.13"
INKSCAPE_APP="/Applications/Inkscape.app"
POTRACE_BIN="/opt/homebrew/Cellar/potrace/1.16/bin/potrace"
POTRACE_LIB="/opt/homebrew/Cellar/potrace/1.16/lib/libpotrace.0.dylib"

rm -rf Resources/BundledPython Resources/BundledBin Resources/ThirdParty
mkdir -p Resources/BundledPython Resources/BundledBin Resources/ThirdParty

rsync -a "$PYTHON_SRC/" Resources/BundledPython/python/

if [ -d "$INKSCAPE_APP" ]; then
  rsync -a "$INKSCAPE_APP/" Resources/ThirdParty/Inkscape.app/
fi

cp "$POTRACE_BIN" Resources/BundledBin/potrace
cp "$POTRACE_LIB" Resources/BundledBin/libpotrace.0.dylib
chmod +x Resources/BundledBin/potrace
install_name_tool -change /opt/homebrew/Cellar/potrace/1.16/lib/libpotrace.0.dylib @executable_path/libpotrace.0.dylib Resources/BundledBin/potrace

xcodegen generate
xcodebuild \
  -project MacShapearator.xcodeproj \
  -scheme MacShapearator \
  -configuration Debug \
  -derivedDataPath build \
  build

APP_PATH="$(pwd)/build/Build/Products/Debug/MacShapearator.app"
echo "Built app: $APP_PATH"
