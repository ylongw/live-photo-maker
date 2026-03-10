#!/usr/bin/env bash
# build.sh — Build LivePhotoMaker.app without Xcode (macOS Command Line Tools only)
# Works locally and on GitHub Actions macos-14 runners.
set -e

SDK=$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk")
OUT_BIN="/tmp/LivePhotoMaker_bin"
APP_BUNDLE="${BUILD_DIR:-$(pwd)}/LivePhotoMaker.app"

echo "🔨 SDK: $SDK"
echo "📦 Output: $APP_BUNDLE"

swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos13.0 \
  -swift-version 5 \
  -parse-as-library \
  -O \
  -framework SwiftUI \
  -framework AVFoundation \
  -framework AVKit \
  -framework Photos \
  -framework CoreGraphics \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  LivePhotoMaker/LivePhotoMakerApp.swift \
  LivePhotoMaker/L10n.swift \
  LivePhotoMaker/ContentView.swift \
  LivePhotoMaker/VideoProcessor.swift \
  LivePhotoMaker/LivePhotoCreator.swift \
  LivePhotoMaker/VideoPlayerView.swift \
  LivePhotoMaker/TimelineView.swift \
  LivePhotoMaker/SavedPreset.swift \
  -o "$OUT_BIN"

echo "📦 Packaging app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$OUT_BIN" "$APP_BUNDLE/Contents/MacOS/LivePhotoMaker"
cp LivePhotoMaker/Info.plist "$APP_BUNDLE/Contents/"
# App icon
if [ -f LivePhotoMaker/AppIcon.icns ]; then
    cp LivePhotoMaker/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
    echo "🎨 Icon: AppIcon.icns"
fi
printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"
chmod +x "$APP_BUNDLE/Contents/MacOS/LivePhotoMaker"

echo "✍️  Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "✅ Built: $APP_BUNDLE"
