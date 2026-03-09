# LivePhotoMaker

Convert any video into an Apple Live Photo on macOS — with full HDR support. No Xcode required.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Release](https://img.shields.io/github/v/release/ylongw/live-photo-maker)

---

## Features

### 🎬 Video Preview & Playback
- Full AVKit player with standard controls
- **HDR badge** auto-detected — shows when source is HLG or PQ

### ✂️ Timeline Trim Selection
- Thumbnail strip showing the full video at a glance
- **Drag the yellow handles** directly on the strip to set start and end
- **Drag the middle** of the selection to pan it (clip duration stays fixed)
- Precision sliders below for fine adjustments

### 🔴 Cover Frame Selection
- Drag the **red marker** on the timeline to pick any frame as the still photo
- **Live preview bubble** — a 96×54 thumbnail floats above the handle while dragging, so you see exactly what frame you're selecting

### 🔁 Loop Preview
- Tick **Loop Preview** → player immediately seeks to the start of your selection and loops within it
- Adjust the trim handles while looping — the range updates in real time
- Confirm the Live Photo video looks right before exporting

### 🌈 HDR-Aware Export
- When an HDR source is detected, an **Export HDR** checkbox appears:
  - ✅ **On** (default) — encodes to **HEVC / H.265**, preserving HLG color space end-to-end
  - ☐ **Off** — encodes to H.264, tone-mapping to SDR
- Cover frame uses `AVAssetImageGenerator` with `dynamicRangePolicy = .matchSource` (macOS 15+) to extract a true HDR `CGImage`; HEIC written with `kCGImageDestinationOptimizeColorForSharing = false` so the HLG color space is preserved

### ⚡ Bitrate Selection
| Option | Codec | Use case |
|--------|-------|---------|
| Low (8 Mbps) | HEVC or H.264 | Share / upload |
| Medium (16 Mbps) | HEVC or H.264 | Balanced (default) |
| High (32 Mbps) | HEVC or H.264 | Archive quality |
| Original | Passthrough | Lossless — no re-encode |

### 📸 Export Options
- **Save to Photos** — imports the Live Photo pair directly into Photos.app via `PHPhotoLibrary` (asks for access on first use)
- **Create Live Photo** — saves the paired HEIC + MOV files to any folder you choose

---

## How Live Photos Work

Apple Live Photos are a **HEIC image + MOV video** pair that share a `Content Identifier` UUID:

| File | Metadata location | Key |
|------|-------------------|-----|
| HEIC | MakerApple EXIF dictionary | key `"17"` via `kCGImagePropertyMakerAppleDictionary` |
| MOV | QuickTime metadata | `com.apple.quicktime.content.identifier` |
| MOV | Timed metadata track | `com.apple.quicktime.still-image-time = -1` |

LivePhotoMaker writes this UUID natively using CoreGraphics and AVFoundation — no external tools required.

When importing via `PHPhotoLibrary.performChanges`, the `.photo` + `.pairedVideo` resource types tell Photos to recognize the pair as a Live Photo automatically.

---

## Requirements

- **macOS 13.0+** (HDR cover frame requires macOS 15+)
- **Apple Silicon (arm64)**
- **Xcode Command Line Tools** — no full Xcode needed

```bash
xcode-select --install
```

---

## Install (from release DMG)

1. Download `LivePhotoMaker.dmg` from [Releases](https://github.com/ylongw/live-photo-maker/releases)
2. Open the DMG and drag **LivePhotoMaker.app** to Applications

### ⚠️ Gatekeeper Warning on First Launch

This app is ad-hoc signed (no paid Apple Developer certificate). macOS will block it on first open.

**Option A — System Settings (no Terminal):**
1. Try to open the app — click **Done** when macOS shows "Not Opened"
2. **System Settings → Privacy & Security**
3. Scroll down → **"LivePhotoMaker was blocked"** → click **Open Anyway**
4. Confirm in the next dialog

**Option B — Terminal:**
```bash
xattr -dr com.apple.quarantine /Applications/LivePhotoMaker.app
```

> Build from source with `./build.sh` on your own machine to avoid Gatekeeper entirely.

---

## Build from Source

```bash
git clone https://github.com/ylongw/live-photo-maker.git
cd live-photo-maker
./build.sh
open LivePhotoMaker.app
```

`build.sh` compiles all Swift sources with `swiftc`, packages the `.app` bundle, and signs it ad-hoc. No Xcode, no Swift Package Manager, no dependencies.

---

## Usage

1. **Open a video** — drag & drop MOV / MP4 / M4V, or click "Open Video"
2. **Trim the clip** — drag the yellow handles on the timeline (recommended: 2–5 s)
3. **Pick a cover frame** — drag the red marker; a preview bubble shows the selected frame
4. **Preview** — tick **Loop Preview** to see exactly how the Live Photo will play
5. **Set quality** — choose bitrate; for HDR sources, keep **Export HDR** checked
6. **Export**:
   - **Save to Photos** → imports directly into Photos.app as a Live Photo
   - **Create Live Photo** → saves HEIC + MOV pair to a folder

---

## Background

macOS doesn't expose `PHAssetResourceType.pairedVideo` at the app level, making programmatic Live Photo creation far harder than on iOS. This project explores the file-format level solution:

- Native UUID injection via CoreGraphics + AVFoundation (no `exiftool`)
- `AVAssetImageGenerator` for HDR-preserving frame extraction (vs. ffmpeg which strips HLG)
- `AVAssetExportSession` for trim + HDR-preserving encode

See also: [`makelive`](https://github.com/RhetTbull/makelive) — the Python equivalent.

---

## License

MIT
