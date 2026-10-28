#!/bin/zsh
# Build Backseat.app (menu-bar app + CLI + MCP server in one binary) and link the `backseat` CLI.
# Usage: build.sh [install dir, default ~/Applications]
set -euo pipefail

HERE=${0:A:h}
APP=${1:-$HOME/Applications}/Backseat.app

mkdir -p $APP/Contents/MacOS $APP/Contents/Resources $HOME/.local/bin
cp $HERE/assets/AppIcon.icns $APP/Contents/Resources/
swiftc -O -swift-version 5 -o $APP/Contents/MacOS/Backseat $HERE/Sources/*.swift

cat > $APP/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Backseat</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>dev.backseat.Backseat</string>
  <key>CFBundleName</key><string>Backseat</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - $APP
ln -sf $APP/Contents/MacOS/Backseat $HOME/.local/bin/backseat
echo "Built $APP; CLI: $HOME/.local/bin/backseat"
