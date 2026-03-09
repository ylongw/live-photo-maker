#!/usr/bin/env bash
# build.sh — Build LivePhotoMaker.app without Xcode (macOS Command Line Tools only)
set -e

SDK=$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")
OUT_BIN="/tmp/LivePhotoMaker_bin"
APP_BUNDLE="LivePhotoMaker.app"

echo "🔨 Compiling..."
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
  LivePhotoMaker/ContentView.swift \
  LivePhotoMaker/VideoProcessor.swift \
  LivePhotoMaker/LivePhotoCreator.swift \
  LivePhotoMaker/VideoPlayerView.swift \
  LivePhotoMaker/TimelineView.swift \
  -o "$OUT_BIN"

echo "📦 Packaging app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$OUT_BIN" "$APP_BUNDLE/Contents/MacOS/LivePhotoMaker"
cp LivePhotoMaker/Info.plist "$APP_BUNDLE/Contents/"
printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"
chmod +x "$APP_BUNDLE/Contents/MacOS/LivePhotoMaker"

echo "✍️  Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "✅ Done! Run with:"
echo "   open $APP_BUNDLE"
