#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app="${PWD}/build/MiniDisplay.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -framework AppKit -framework CoreGraphics Sources/MiniDisplay.swift -o "$app/Contents/MacOS/MiniDisplay"
cp Resources/DisplayProductID-2750 "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MiniDisplay</string>
<key>CFBundleIdentifier</key><string>local.yikesai.MiniDisplay</string>
<key>CFBundleName</key><string>MiniDisplay</string>
<key>CFBundleDisplayName</key><string>MiniDisplay</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "$app"
