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

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Pumpkin Porch</string>
    <key>CFBundleDisplayName</key><string>Pumpkin Porch</string>
    <key>CFBundleIdentifier</key><string>local.pumpkinporch</string>
    <key>CFBundleExecutable</key><string>PumpkinPorch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# Sign it locally so macOS is happy running it (no Apple account needed).
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "✅ Done! Double-click \"$APP\" to start it."
echo "   Look for the 🎃 in your menu bar to control it or quit."
