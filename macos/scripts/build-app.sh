#!/bin/bash
# Build "Local Postman.app" from the Swift package, and optionally install it.
#
#   scripts/build-app.sh            -> macos/dist/Local Postman.app
#   scripts/build-app.sh --install  -> also copies it to /Applications and opens it
#
# Needs Xcode 26 (the macOS 26 SDK) selected: `xcode-select -p` should point into it.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="2.0"
APP="dist/Local Postman.app"

swift build -c release --product LocalPostman
BIN="$(swift build -c release --show-bin-path)/LocalPostman"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LocalPostman"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Local Postman</string>
    <key>CFBundleDisplayName</key><string>Local Postman</string>
    <key>CFBundleIdentifier</key><string>cz.matejalexander.local-postman.native</string>
    <key>CFBundleExecutable</key><string>LocalPostman</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <!-- An API client has to reach plain-http dev servers and anything on the LAN. -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><true/>
        <key>NSAllowsLocalNetworking</key><true/>
    </dict>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Local Postman sends the requests you build to servers on your network.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for your own machine, not for distribution.
codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/Local Postman.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/Local Postman.app"
    open "/Applications/Local Postman.app"
fi
