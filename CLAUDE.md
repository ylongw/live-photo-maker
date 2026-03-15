# CLAUDE.md — Agent Developer Guide

> Read this first. It tells you everything you need to get productive in < 5 minutes.

## What This Project Is

**LivePhotoMaker** is a macOS SwiftUI app that converts any video (MOV/MP4/M4V) into an Apple Live Photo and imports it into Photos.app.

Key capabilities:
- **HDR preservation** — cover frame via `AVAssetImageGenerator` preserves HLG/PQ color space
- **Color grading** — Auto Enhance (CIAutoAdjust) + 10 manual sliders applied to both cover HEIC and video MOV
- **Portrait video support** — auto-detects vertical video and switches to side-by-side layout
- **Batch queue** — sidebar file list with drag-in / keyboard shortcuts

## Architecture

```
LivePhotoMaker/
├── LivePhotoMakerApp.swift   — @main entry point, SwiftUI App
├── ContentView.swift         — main UI: drop zone, player, timeline, controls, export
├── VideoProcessor.swift      — AVAssetExportSession: trim video, detect HDR, color grade
├── LivePhotoCreator.swift    — UUID stamping (HEIC + MOV), PHPhotoLibrary import
├── VideoPlayerView.swift     — AVPlayerView wrapper (NSViewRepresentable)
├── TimelineView.swift        — timeline scrubber with thumbnail strips + cover handle
├── ColorGrade.swift          — ColorGrade struct + CIFilter pipeline (10 params)
├── SavedPreset.swift         — PresetStore: named export presets (UserDefaults)
└── L10n.swift                — Bilingual strings (zh/en), singleton L10n.shared
```

### Data Flow

```
User drops video
  → ContentView loads AVURLAsset
  → VideoProcessor.loadAsset() — detect HDR, duration, portrait
  → User trims clip, picks cover frame, adjusts color grade
  → ContentView.exportLivePhoto() or exportAndImportToPhotos()
      ├── VideoProcessor.exportVideo(grade:autoFilterParams:)
      │     → resolveAVPreset() → AVAssetExportSession
      │     → if grade active: AVMutableVideoComposition(applyingCIFiltersWithHandler:)
      ├── ColorGrade.apply(to:) on cover CGImage
      └── LivePhotoCreator.createLivePhoto(coverImage:videoURL:coverOffset:)
            → writeImageWithContentIdentifier() — HEIC + UUID + kCGImagePropertyMakerAppleDictionary["17"]
            → writeVideoWithContentIdentifier() — MOV + UUID + still-image-time (float32 seconds)
```

## Key Technical Decisions

| Decision | Why |
|----------|-----|
| `AVAssetImageGenerator` for cover frame | Only way to preserve HLG CGColorSpace; ffmpeg tone-maps to SDR |
| `kCGImagePropertyMakerAppleDictionary["17"]` | Apple MakerNote key for Live Photo UUID in HEIC |
| `still-image-time = coverTime - startTime` (float32) | Correct value enables "Make Key Photo" in Photos.app; -1 disables it |
| `AVMutableVideoComposition(applyingCIFiltersWithHandler:)` | Per-frame CIFilter GPU pipeline for color grade |
| `@State colorGrade: ColorGrade` in ContentView | CIFilter params captured as value type for thread-safe AVVideoComposition closure |
| Auto-enhance serializes filter params `[(name, params)]` | CIFilter is not thread-safe; recreate per frame |
| `playerItem.videoComposition` updated in-place | Loop Preview shows grade without re-creating player |
| `ExportSettings.codec = .hevc` default | HEVC ~8Mbps 1080p ≈ iPhone Live Photo quality |
| Settings persist across file switches | Only HDR flag and color grade reset on new file |

## Color Grading (ColorGrade.swift)

`ColorGrade` is a value-type struct (Equatable). All defaults = identity (no visual change).

| Property | CIFilter | Neutral | Range |
|----------|---------|---------|-------|
| exposure | CIExposureAdjust inputEV | 0 | -3…+3 |
| contrast | CIColorControls inputContrast | 1 | 0.5…1.5 |
| brightness | CIColorControls inputBrightness | 0 | -0.5…+0.5 |
| saturation | CIColorControls inputSaturation | 1 | 0…2 |
| highlights | CIHighlightShadowAdjust inputHighlightAmount | 1 | 0…1 |
| shadows | CIHighlightShadowAdjust inputShadowAmount | 0 | 0…1 |
| vibrance | CIVibrance inputAmount | 0 | -1…+1 |
| sharpness | CISharpenLuminance inputSharpness | 0 | 0…2 |
| warmth | CITemperatureAndTint offset | 0 | -100…+100 (×30K) |
| tint | CITemperatureAndTint Y | 0 | -100…+100 |

Auto Enhance uses `CIImage.autoAdjustmentFilters()` — same API as Apple Photos' magic wand.
Filter params are serialized to `[(name: String, params: [String: Any])]` for thread-safe use in `AVMutableVideoComposition`.

## Compile Command (no Xcode needed)

```bash
swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
  -target arm64-apple-macos13.0 -swift-version 5 -parse-as-library -O \
  -framework SwiftUI -framework AVFoundation -framework AVKit \
  -framework Photos -framework CoreGraphics -framework AppKit \
  -framework UniformTypeIdentifiers \
  LivePhotoMaker/LivePhotoMakerApp.swift \
  LivePhotoMaker/L10n.swift \
  LivePhotoMaker/ColorGrade.swift \
  LivePhotoMaker/ContentView.swift \
  LivePhotoMaker/VideoProcessor.swift \
  LivePhotoMaker/LivePhotoCreator.swift \
  LivePhotoMaker/VideoPlayerView.swift \
  LivePhotoMaker/TimelineView.swift \
  LivePhotoMaker/SavedPreset.swift \
  -o /tmp/LivePhotoMaker_bin
```

Or use `./build.sh` (builds into `~/Desktop/LivePhotoMaker.app`).

## onChange API Compatibility

Target is macOS 13. Use the two-argument form:
```swift
.onChange(of: someValue) { newValue in ... }   // ✅ macOS 13+
.onChange(of: someValue) { _, newValue in ... } // ❌ macOS 14+ only
```

## CI/CD

GitHub Actions `.github/workflows/release.yml` — triggers on `v*` tags, `macos-15` runner.
Build uses `./build.sh`, packages into DMG, uploads to GitHub Release.

Tag a release:
```bash
git tag -a v1.x.0 -m "v1.x.0 — description" && git push origin v1.x.0
```

## Common Gotchas

- `AVAssetExportPresetPassthrough` cannot have `videoComposition` set — auto-upgrades to `HighestQuality` when color grade is active
- `still-image-time` must be the cover frame offset within the **trimmed** clip, not absolute time in original asset
- `AVMutableVideoComposition(asset:applyingCIFiltersWithHandler:)` is synchronous (macOS 10.11+), not async
- Auto-enhance filter params reset when user changes startTime/endTime (clip changed → stale analysis)
- `onChange(of:initial:_:)` two-arg new form is macOS 14+ only
