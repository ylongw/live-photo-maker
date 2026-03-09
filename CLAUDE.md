# CLAUDE.md — Agent Developer Guide

> Read this first. It tells you everything you need to get productive in < 5 minutes.

## What This Project Is

**LivePhotoMaker** is a macOS SwiftUI app that converts any video (MOV/MP4/M4V) into an Apple Live Photo and imports it into Photos.app.

Key capability: **full HDR preservation** — the cover frame is extracted via `AVAssetImageGenerator` (not ffmpeg), which preserves HLG/PQ color space through the native `CGImage` / `CGColorSpace` pipeline.

## Architecture

```
LivePhotoMaker/
├── LivePhotoMakerApp.swift   — @main entry point, SwiftUI App
├── ContentView.swift         — main UI: drop zone, player, timeline, export buttons
├── VideoProcessor.swift      — AVAssetExportSession: trim video, detect HDR
├── LivePhotoCreator.swift    — UUID stamping (HEIC + MOV), PHPhotoLibrary import
├── VideoPlayerView.swift     — AVPlayerView wrapper (NSViewRepresentable)
└── TimelineView.swift        — custom timeline scrubber with thumbnail strips
```

### Data Flow

```
User drops video
  → ContentView loads AVURLAsset
  → VideoProcessor.exportVideo() — trim + HDR preserve → trimmed .mov in /tmp
  → AVAssetImageGenerator.image(at:) — extract cover CGImage (preserves colorSpace)
  → LivePhotoCreator.createLivePhoto()
      → writeImageWithContentIdentifier() → HEIC via CGImageDestination
          kCGImagePropertyMakerAppleDictionary key "17" = UUID
      → writeVideoWithContentIdentifier() → MOV via AVAssetExportSession passthrough
          com.apple.quicktime.content.identifier = same UUID
          com.apple.quicktime.still-image-time = -1
  → importToPhotos() → PHPhotoLibrary.performChanges
      .photo + .pairedVideo resource types → Photos recognizes as Live Photo
```

### Live Photo UUID Pairing

A Live Photo is a **HEIC + MOV pair sharing one Content Identifier UUID**:

| File | Location | Key |
|------|----------|-----|
| HEIC | MakerApple EXIF dict | key `"17"` via `kCGImagePropertyMakerAppleDictionary` |
| MOV  | QuickTime metadata | `com.apple.quicktime.content.identifier` |
| MOV  | Timed metadata track | `com.apple.quicktime.still-image-time = -1` |

> **Critical**: `PHPhotoLibrary.performChanges` with `.photo + .pairedVideo` handles pairing automatically by resource type. The UUID is only needed for file-system-based pairing (e.g. drag to Photos).

### HDR Pipeline

- **Cover frame**: `AVAssetImageGenerator` returns `CGImage` with original `CGColorSpace` intact (HLG/PQ preserved). Written to HEIC via `CGImageDestinationAddImage` — color space embedded automatically.
- **Video**: `AVAssetExportSession` with `AVAssetExportPresetHighestQuality` preserves HDR color metadata in the output MOV. Do **not** use ffmpeg for frame extraction — it strips HLG metadata.
- **Detection**: `AVMediaCharacteristic.containsHDRVideo` on the video track.

## Build

```bash
# No Xcode required — only Command Line Tools
xcode-select --install   # if not already installed

./build.sh               # compiles + packages LivePhotoMaker.app + ad-hoc signs
open LivePhotoMaker.app
```

`build.sh` uses:
- `swiftc -swift-version 5 -target arm64-apple-macos13.0`
- All frameworks linked dynamically (system-provided on macOS 13+)
- `codesign --sign -` (ad-hoc)

## Release Workflow

Releases are built automatically by GitHub Actions on tag push.

```bash
# When ready to release a new version:
git tag -a v1.x.x -m "changelog here"
git push origin v1.x.x
# → .github/workflows/release.yml triggers
# → macos-14 runner: build.sh → hdiutil DMG → softprops/action-gh-release upload
```

The workflow file is at `.github/workflows/release.yml`.

## Known Issues / Gotchas

| Issue | Root Cause | Fix / Status |
|-------|-----------|--------------|
| Gatekeeper "Not Opened" | Ad-hoc signing, no notarization | Users: System Settings → Privacy & Security → Open Anyway, or `xattr -dr com.apple.quarantine` |
| Swift 6 actor crash (old) | `swift_task_isMainExecutorImpl` null deref without full Xcode bootstrap | Fixed: compile with `-swift-version 5` |
| AVAssetWriter deadlock (old) | `requestMediaDataWhenReady` + `withCheckedContinuation` deadlock under Swift actor scheduling | Fixed: replaced with `AVAssetExportSession` passthrough |
| Swift 5.9 CI concurrency error | `[weak self]` inside nested `Task { @MainActor }` | Fixed: `Task { @MainActor [weak self] in }` |
| `AVAssetExportSession` non-Sendable warning | `session` captured in Timer closure | Warning only, not error; safe to ignore |

## Testing

No XCTest suite yet. Manual test protocol:

1. Drop `~/Downloads/C0971.MP4` (Sony XAVC 4K HLG) into the app
2. Set clip 0:00–0:03, cover at 0:01.5, bitrate Medium
3. Click **Save to Photos** → grant access → verify LIVE badge appears in Photos.app
4. Click **Create Live Photo** → verify `IMG_*.heic` + `IMG_*.mov` pair exported with matching UUID

Verify UUID match:
```bash
mdls -name kMDItemContentType /path/to/IMG_*.heic
# Use exiftool to check MakerApple tag 17 vs MOV content.identifier
```

## Source Video Used for Development

- File: `C0971.MP4` (Sony XAVC, 9.01s, 4K 3840×2160, H.264 High 4:2:2 10-bit, HLG arib-std-b67, bt2020, 29.97fps, 192MB)
- Available locally at `~/Downloads/C0971.MP4` on the dev machine

## What to Work On Next

- [ ] **Notarization** — add Apple Developer cert to GitHub Actions secrets for automatic Gatekeeper bypass
- [ ] **Intel support** — add `x86_64` target to build.sh for universal binary
- [ ] **XCTest suite** — unit tests for `LivePhotoCreator` UUID injection
- [ ] **Progress polish** — per-step progress feedback (extracting frame / exporting video / writing UUID / importing)
- [ ] **Drag-and-drop cover preview** — show extracted HDR frame in a preview panel before export
- [ ] **`.pvt` package export** — Apple's private Live Photo bundle format for direct share
