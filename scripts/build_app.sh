#!/usr/bin/env bash
set -euo pipefail

# Directory roots
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_SRC_DIR="$WORKSPACE_ROOT/app"
DIST_DIR="$WORKSPACE_ROOT/dist"
APP_BUNDLE="$DIST_DIR/Fmr.app"

echo "==> Building Zig core binary..."
cd "$WORKSPACE_ROOT"
zig build

echo "==> Building Swift App (Release)..."
cd "$APP_SRC_DIR"
swift build -c release

SWIFT_BIN="$APP_SRC_DIR/.build/release/FmrApp"
ZIG_BIN="$WORKSPACE_ROOT/zig-out/bin/fmr"

# Core version reported by fmr --version (e.g. "fmr 0.1.0").
FMR_VERSION=$("$ZIG_BIN" --version | awk '{print $2}')
if [ -z "$FMR_VERSION" ]; then
    FMR_VERSION="0.0.0"
fi

echo "==> Creating macOS Application Bundle ($APP_BUNDLE) (core v$FMR_VERSION)..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Helpers"

# Copy binaries
cp "$SWIFT_BIN" "$APP_BUNDLE/Contents/MacOS/FmrApp"
cp "$ZIG_BIN" "$APP_BUNDLE/Contents/Helpers/fmr"
chmod +x "$APP_BUNDLE/Contents/MacOS/FmrApp"
chmod +x "$APP_BUNDLE/Contents/Helpers/fmr"

# Generate Info.plist. LSUIElement=true => menu-bar-only app (no Dock icon).
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FmrApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.drawmeanelephant.fmr</string>
    <key>CFBundleName</key>
    <string>Fmr</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$FMR_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$FMR_VERSION</string>
    <key>FMRCoreVersion</key>
    <string>$FMR_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc codesign so macOS (Apple Silicon) launches the unsigned GUI binary.
echo "==> Codesigning bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "==> Done! Application bundle created at: $APP_BUNDLE"
echo "    You can run it with: open '$APP_BUNDLE'"
