# LivePhotoMaker

A macOS app to convert any video clip into an Apple Live Photo and save it directly to Photos.app — with full HDR support.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Video preview** with AVKit player
- **Timeline scrubber** — drag to select cover frame and trim start/end points
- **HDR-aware export** — preserves HLG / PQ transfer functions and BT.2020 color primaries via AVFoundation (no color shift)
- **Bitrate selection** — Low (8 Mbps) / Medium (16 Mbps) / High (32 Mbps) / Original passthrough
- **HDR detection badge** — automatically detects HLG and PQ source videos
- **Save to Photos** — imports the Live Photo pair directly into Photos.app via `PHPhotoLibrary`
- **Create Live Photo** — export as paired HEIC + MOV files to a folder of your choice
- Supports MOV, MP4, M4V input

## How It Works

Apple Live Photos are a paired **HEIC/JPEG image + MOV video** that share the same `Content Identifier` UUID:

- The HEIC stores the UUID in `kCGImagePropertyMakerAppleDictionary` key `"17"` (Apple Maker Notes)
- The MOV stores the UUID as `com.apple.quicktime.content.identifier` QuickTime metadata

LivePhotoMaker uses:
- `AVAssetImageGenerator` to extract the cover frame as a `CGImage` — preserving the original color space (HLG, PQ, or SDR) for true HDR stills
- `AVAssetExportSession` to trim and re-encode the video while preserving HDR metadata
- `CGImageDestination` + `AVAssetExportSession` passthrough to stamp both files with a matching UUID
- `PHPhotoLibrary.performChanges` with `.photo` + `.pairedVideo` resource types to import into Photos

## Requirements

- macOS 13.0+
- **Xcode Command Line Tools** (no full Xcode required)

```bash
xcode-select --install
```

## Build & Run

```bash
git clone https://github.com/ylongwang2782/live-photo-maker.git
cd live-photo-maker
./build.sh
open LivePhotoMaker.app
```

The build script compiles all Swift sources with `swiftc`, packages the `.app` bundle, and signs it ad-hoc. No Xcode, no SPM, no dependencies.

## Usage

1. **Open a video** — drag & drop or click "Open Video" (MOV / MP4 / M4V)
2. **Set clip range** — drag the yellow handles on the timeline to choose start and end (recommended: 2–5 seconds)
3. **Set cover frame** — drag the red marker to the moment you want as the still photo
4. **Choose bitrate** — or keep "Original" for lossless passthrough
5. **Export**:
   - **Save to Photos** — imports directly into Photos.app (grants access on first use)
   - **Create Live Photo** — saves the HEIC + MOV pair to a folder you choose

## HDR Note

When the source video is HDR (HLG or PQ), the cover frame extracted by `AVAssetImageGenerator` carries the original `CGColorSpace` — the HEIC is written with the correct color space for true HDR display on supported screens. The exported MOV retains the original HDR metadata via `AVAssetExportSession`.

## ⚠️ First Launch: Gatekeeper Warning

The release DMG is **ad-hoc signed** (no paid Apple Developer certificate), so macOS will show a security warning on first launch.

### Method 1 — System Settings (no Terminal needed)

1. Try to open the app — macOS will show "Not Opened" dialog. Click **Done**.
2. Open **System Settings → Privacy & Security**
3. Scroll down — you'll see **"LivePhotoMaker was blocked from use because it is not from an identified developer"**
4. Click **Open Anyway** → confirm in the next dialog

### Method 2 — Terminal

```bash
xattr -dr com.apple.quarantine /Applications/LivePhotoMaker.app
```

Then double-click the app normally.

> **Why this happens:** Apple requires a $99/year Developer account and notarization to bypass Gatekeeper automatically. Building from source with `./build.sh` on your own machine avoids this entirely.

## Background

This project grew out of exploring the Live Photo file format on macOS, where Apple's `PHAssetResourceType.pairedVideo` is unavailable, making programmatic Live Photo creation much harder than on iOS. See [`makelive`](https://github.com/RhetTbull/makelive) for the Python equivalent using CoreGraphics + AVFoundation directly.

## License

MIT
