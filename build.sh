#!/bin/bash
# Build CursorHop.app with only the Xcode Command Line Tools (no Xcode project needed).
#
#   ./build.sh            build for this Mac's architecture -> build/CursorHop.app
#   ./build.sh universal  build for Apple Silicon + Intel
#   ./build.sh install    build, copy to /Applications, and launch
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc not found. Install the Command Line Tools first:  xcode-select --install" >&2
    exit 1
fi

APP="build/CursorHop.app"
BIN="$APP/Contents/MacOS/CursorHop"
MODE="${1:-}"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile() { # $1 = arch, $2 = output
    swiftc -O -whole-module-optimization \
        -target "$1-apple-macos13.0" \
        -framework AppKit -framework Carbon -framework ServiceManagement \
        CursorHop/*.swift -o "$2"
}

if [[ "$MODE" == "universal" ]]; then
    echo "Compiling arm64…";  compile arm64  build/CursorHop-arm64
    echo "Compiling x86_64…"; compile x86_64 build/CursorHop-x86_64
    lipo -create build/CursorHop-arm64 build/CursorHop-x86_64 -output "$BIN"
    rm build/CursorHop-arm64 build/CursorHop-x86_64
else
    ARCH="$(uname -m)"
    echo "Compiling for $ARCH…"
    compile "$ARCH" "$BIN"
fi

cp CursorHop/Info.plist "$APP/Contents/Info.plist"
cp CursorHop/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" # regenerate: swift scripts/make_icon.swift
# Ad-hoc sign so macOS (especially Apple Silicon) runs it and Login Items work.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "$MODE" == "install" ]]; then
    pkill -x CursorHop 2>/dev/null || true
    rm -rf /Applications/CursorHop.app
    cp -R "$APP" /Applications/
    open /Applications/CursorHop.app
    echo "Installed to /Applications and launched. Look for the cursor icon in the menu bar."
fi
