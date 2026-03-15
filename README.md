# LivePhotoMaker

Convert any video into an Apple Live Photo on macOS. No Xcode required.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Release](https://img.shields.io/github/v/release/ylongw/live-photo-maker)

---

## Features

### 🎬 Video Preview & Timeline
- Full AVKit player with standard controls
- Thumbnail strip timeline — **drag yellow handles** to set start/end, **drag red marker** to pick cover frame
- **Live preview bubble** floats above the cover marker while dragging
- **Loop Preview** — loops within the selected clip range; updates in real time as you adjust handles
- **Seek to Cover** — jumps playhead to the current cover frame position

### ✂️ Clip Trimming
- Drag handles or use precision sliders; total / clip duration shown
- Platform presets: **小红书 XHS** (≤2.8 s, H.264 720p SDR) and **抖音** automatically fill recommended values

### 🎨 Color Grading (NEW)
- **Auto Enhance** — one checkbox runs `CIImage.autoAdjustmentFilters()` (the same API as Apple Photos' magic wand) on the cover frame, derives color adjustments, and applies them uniformly to every video frame — no flicker
- **10 manual sliders** (expand the Color Grade panel): Exposure / Contrast / Brightness / Highlights / Shadows / Saturation / Vibrance / Sharpness / **Warmth** / **Tint**
- Loop Preview reflects color grade in real time via `AVPlayerItem.videoComposition`
- Color grade applied to both the cover HEIC and the exported MOV
- Auto Enhance resets when you change the clip selection (stale analysis warning)

### 🌈 HDR-Aware Export
- **Export HDR** checkbox appears automatically when an HLG/PQ source is detected
- HDR path: HEVC + `dynamicRangePolicy = .matchSource` on `AVAssetImageGenerator`; HEIC written with `kCGImageDestinationOptimizeColorForSharing = false`

### ⚙️ Flexible Export Settings
| Setting | Options |
|---------|---------|
| Codec | H.264 / HEVC (H.265, default) |
| Resolution | 720p / 1080p / 4K / Source |
| Quality | Low / High / Source (passthrough) |
| Frame Rate | 24 / 30 / 60 / Source |
| Audio | Keep / **Mute** |
| HDR | On / Off (SDR sources: N/A) |

### 📁 File Queue Sidebar
- Drag multiple files into the sidebar to build a batch list
- Click to switch between files; settings persist across switches
- Right-click → **Remove from List** or **Move to Trash**; `⌘⌫` to trash the selected file

### 🌐 Bilingual UI
- Default: Chinese (中文) — click **EN** in the top bar to switch to English; preference persists

### 📸 Export Options
- **Save to Photos** — imports the Live Photo pair directly into Photos.app via `PHPhotoLibrary`
- **Create Live Photo** — saves HEIC + MOV files to any folder you choose

---

## How Live Photos Work

Apple Live Photos are a **HEIC image + MOV video** pair sharing a `Content Identifier` UUID:

| File | Key | Value |
|------|-----|-------|
| HEIC | `kCGImagePropertyMakerAppleDictionary["17"]` | UUID string |
| MOV | `com.apple.quicktime.content.identifier` | same UUID |
| MOV | `com.apple.quicktime.still-image-time` | cover frame offset (seconds, float32) |

LivePhotoMaker writes all metadata natively via CoreGraphics + AVFoundation — no `exiftool` required.

> **Make Key Photo** in iOS Photos requires `still-image-time` to be the actual time offset of the cover frame within the trimmed clip, not the sentinel value `-1`.

---

## Requirements

- **macOS 13.0+** (HDR cover frame requires macOS 15+)
- **Apple Silicon (arm64)**
- **Xcode Command Line Tools**

```bash
xcode-select --install
```

---

## Install

1. Download `LivePhotoMaker.dmg` from [Releases](https://github.com/ylongw/live-photo-maker/releases)
2. Open the DMG → drag **LivePhotoMaker.app** to Applications

### ⚠️ Gatekeeper on First Launch

**System Settings → Privacy & Security → Open Anyway**, or:

```bash
xattr -dr com.apple.quarantine /Applications/LivePhotoMaker.app
```

---

## Build from Source

```bash
git clone https://github.com/ylongw/live-photo-maker.git
cd live-photo-maker
./build.sh
open LivePhotoMaker.app
```

No Xcode, no Swift Package Manager, no dependencies.

---

## License

MIT
