#!/bin/bash
# Builds DeviceDeck in release mode and bundles it into build/DeviceDeck.app
set -euo pipefail

# Resolve the package root (this script lives in scripts/). Paths may contain spaces.
PACKAGE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PACKAGE_ROOT"

echo "==> Building DeviceDeck (release)..."
swift build -c release

APP_DIR="$PACKAGE_ROOT/build/DeviceDeck.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Creating app bundle structure..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

BIN_PATH="$(swift build -c release --show-bin-path 2>/dev/null || true)"
if [ -z "$BIN_PATH" ] || [ ! -f "$BIN_PATH/DeviceDeck" ]; then
    BIN_PATH="$PACKAGE_ROOT/.build/release"
fi

cp "$BIN_PATH/DeviceDeck" "$MACOS_DIR/DeviceDeck"

# ---------------------------------------------------------------------------
# App icon (best effort — never fails the build)
# ---------------------------------------------------------------------------
ICON_GENERATED=0
SCRIPT_DIR="$PACKAGE_ROOT/scripts"
generate_icon() {
    local TMP_ICON_DIR
    TMP_ICON_DIR="$(mktemp -d)"
    local PNG_1024="$TMP_ICON_DIR/icon_1024.png"
    local ICONSET_DIR="$TMP_ICON_DIR/DeviceDeck.iconset"

    swift "$SCRIPT_DIR/make-icon.swift" "$TMP_ICON_DIR" || return 1
    [ -f "$PNG_1024" ] || return 1

    mkdir -p "$ICONSET_DIR"
    local SIZES=(16 32 64 128 256 512)
    for SIZE in "${SIZES[@]}"; do
        sips -z "$SIZE" "$SIZE" "$PNG_1024" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" >/dev/null || return 1
        local DOUBLE=$((SIZE * 2))
        if [ "$DOUBLE" -eq 1024 ]; then
            cp "$PNG_1024" "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" || return 1
        else
            sips -z "$DOUBLE" "$DOUBLE" "$PNG_1024" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" >/dev/null || return 1
        fi
    done

    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/DeviceDeck.icns" || return 1
    rm -rf "$TMP_ICON_DIR"
    return 0
}

echo "==> Generating app icon..."
if generate_icon; then
    ICON_GENERATED=1
    echo "    Icon generated."
else
    echo "    Icon generation failed; continuing without an icon."
fi

# ---------------------------------------------------------------------------
# Info.plist
# ---------------------------------------------------------------------------
echo "==> Writing Info.plist..."
ICON_KEY=""
if [ "$ICON_GENERATED" -eq 1 ]; then
    ICON_KEY="    <key>CFBundleIconFile</key>
    <string>DeviceDeck</string>"
fi

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DeviceDeck</string>
    <key>CFBundleDisplayName</key>
    <string>DeviceDeck</string>
    <key>CFBundleIdentifier</key>
    <string>com.devicedeck.app</string>
    <key>CFBundleExecutable</key>
    <string>DeviceDeck</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
${ICON_KEY}
    <key>NSLocalNetworkUsageDescription</key>
    <string>DeviceDeck discovers and connects to your other Apple devices on your local network for file sharing and device management.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_devicedeck-fs._tcp</string>
        <string>_devicedeck-fs._udp</string>
    </array>
</dict>
</plist>
EOF

# ---------------------------------------------------------------------------
# Code signing (ad hoc)
# ---------------------------------------------------------------------------
echo "==> Code signing (ad hoc)..."
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "Done. App bundle:"
echo "$APP_DIR"
