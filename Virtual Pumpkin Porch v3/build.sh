#!/bin/bash
# Builds "Pumpkin Porch.app" next to this script.
# Needs Apple's free Command Line Tools:  xcode-select --install
set -e
cd "$(dirname "$0")"

APP="Pumpkin Porch.app"
echo "🎃 Carving pumpkins..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O PumpkinPorch.swift -o "$APP/Contents/MacOS/PumpkinPorch"

# App icon: turn AppIcon.png into a proper macOS .icns with Apple's own tools.
mkdir -p "$APP/Contents/Resources"
if [ -f AppIcon.png ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET")"
else
    echo "(No AppIcon.png found next to build.sh, so the app gets the default icon.)"
fi

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Pumpkin Porch</string>
    <key>CFBundleDisplayName</key><string>Pumpkin Porch</string>
    <key>CFBundleIdentifier</key><string>local.pumpkinporch</string>
    <key>CFBundleExecutable</key><string>PumpkinPorch</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>3.0</string>
    <key>CFBundleShortVersionString</key><string>3.0</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# Sign it locally so macOS is happy running it (no Apple account needed).
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

# Nudge Finder to show the new icon straight away.
touch "$APP"

echo "✅ Done! Double-click \"$APP\" to start it."
echo "   Click the 🎃 in your menu bar to open the control panel."
