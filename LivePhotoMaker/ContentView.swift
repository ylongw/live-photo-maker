import SwiftUI
import AVKit
import AVFoundation
import AppKit
import UniformTypeIdentifiers

// ── File queue item ────────────────────────────────────────────────────────────
struct FileQueueItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    static func == (a: FileQueueItem, b: FileQueueItem) -> Bool { a.url == b.url }
}

// ── Main view ──────────────────────────────────────────────────────────────────
struct ContentView: View {
    @StateObject private var processor = VideoProcessor()
    @State private var player: AVPlayer?
    @State private var asset: AVAsset?
    @State private var videoURL: URL?

    // ── File queue ───────────────────────────────────────────────────────────
    @State private var fileQueue: [FileQueueItem] = []
    @State private var currentQueueIndex: Int = -1

    @State private var coverTime: Double = 0
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var exportSettings = ExportSettings()
    @State private var platformPreset: PlatformPreset = .custom

    // ── Custom preset store ──────────────────────────────────────────────────
    @StateObject private var presetStore = PresetStore()
    @State private var activeCustomPreset: SavedPreset? = nil
    @State private var showingSaveField = false
    @State private var newPresetName = ""
    @State private var thumbnails: [NSImage] = []

    @State private var isDragOver = false
    @State private var showError = false
    @State private var errorMessage = ""

    /// Live preview frame shown above the red cover-time handle.
    @State private var coverFramePreview: NSImage?
    /// Cancellable task for debounced cover frame extraction.
    @State private var coverPreviewTask: Task<Void, Never>?

    /// When true, AVPlayer loops between startTime and endTime.
    @State private var isLoopPreview = false
    /// Opaque token from addBoundaryTimeObserver; must be removed before player changes.
    @State private var loopObserver: Any? = nil

    var body: some View {
        HStack(spacing: 0) {
            // ── File queue sidebar ───────────────────────────────────────────
            if !fileQueue.isEmpty {
                fileSidebarView
                Divider()
            }

            // ── Main editing area ────────────────────────────────────────────
            mainEditingArea
        }
        .frame(minWidth: fileQueue.isEmpty ? 700 : 870, minHeight: 550)
        .alert("Error", isPresented: $showError) { Button("OK") {} } message: { Text(errorMessage) }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { handleDrop(providers: $0) }
    }

    // ── File queue sidebar view ────────────────────────────────────────────────
    private var fileSidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Files")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: openVideoFile) {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Add more videos")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(fileQueue.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 7) {
                            Image(systemName: index == currentQueueIndex
                                  ? "film.fill" : "film")
                                .font(.caption)
                                .foregroundColor(index == currentQueueIndex ? .accentColor : .secondary)
                            Text(item.name)
                                .font(.caption2)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .foregroundColor(index == currentQueueIndex ? .primary : .secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(index == currentQueueIndex
                                      ? Color.accentColor.opacity(0.15)
                                      : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { switchToFile(at: index) }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
        .frame(width: 170)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // ── Main editing area ──────────────────────────────────────────────────────
    private var mainEditingArea: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("LivePhotoMaker")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Current filename
                if let url = videoURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                }

                Spacer()
                if processor.isHDR {
                    Label("HDR", systemImage: "sparkles.tv")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.purple.opacity(0.2)))
                        .foregroundColor(.purple)
                }
            }
            .padding()

            Divider()

            if let player = player {
                // Video loaded state
                ScrollView {
                    VStack(spacing: 16) {
                        // Video preview
                        VideoPlayerView(player: player)
                            .frame(minHeight: 300, maxHeight: 400)
                            .cornerRadius(8)
                            .padding(.horizontal)

                        // Timeline
                        TimelineView(
                            duration: processor.duration,
                            coverTime: $coverTime,
                            startTime: $startTime,
                            endTime: $endTime,
                            thumbnails: thumbnails,
                            coverFramePreview: coverFramePreview
                        )
                        .padding(.horizontal)
                        .padding(.top, coverFramePreview != nil ? 60 : 0) // room for the popup
                        .onChange(of: coverTime) { newTime in
                            // Debounced cover frame extraction (150 ms)
                            coverPreviewTask?.cancel()
                            coverPreviewTask = Task {
                                try? await Task.sleep(nanoseconds: 150_000_000)
                                guard !Task.isCancelled, let asset = asset else { return }
                                let time = CMTime(seconds: newTime, preferredTimescale: 600)
                                if let cgImage = try? await processor.extractCoverFrame(asset: asset, at: time) {
                                    coverFramePreview = NSImage(
                                        cgImage: cgImage,
                                        size: NSSize(width: cgImage.width, height: cgImage.height)
                                    )
                                }
                            }
                        }

                        // Controls
                        VStack(spacing: 12) {

                            // ── Platform preset picker + save ─────────────────
                            HStack(spacing: 8) {
                                Text("Optimized for:")
                                    .font(.subheadline)
                                ForEach(PlatformPreset.allCases) { preset in
                                    Button(preset.label) {
                                        applyPlatformPreset(preset)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(platformPreset == preset && activeCustomPreset == nil
                                          ? .accentColor : .secondary)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(platformPreset == preset && activeCustomPreset == nil
                                                  ? Color.accentColor.opacity(0.12)
                                                  : Color.clear)
                                    )
                                }
                                Spacer()

                                // Save current settings as named preset
                                if showingSaveField {
                                    HStack(spacing: 4) {
                                        TextField("Preset name…", text: $newPresetName)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 150)
                                            .onSubmit { commitSavePreset() }
                                        Button("Save") { commitSavePreset() }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                            .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                                        Button("Cancel") {
                                            showingSaveField = false
                                            newPresetName = ""
                                        }
                                        .buttonStyle(.borderless)
                                        .controlSize(.small)
                                        .foregroundColor(.secondary)
                                    }
                                } else {
                                    Button {
                                        showingSaveField = true
                                    } label: {
                                        Label("Save Preset", systemImage: "square.and.arrow.down")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Save current export settings as a named preset")
                                }
                            }

                            // ── My presets row (visible only when presets exist) ──
                            if !presetStore.presets.isEmpty {
                                HStack(spacing: 6) {
                                    Text("My Presets:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 5) {
                                            ForEach(presetStore.presets) { preset in
                                                HStack(spacing: 2) {
                                                    Button(preset.name) {
                                                        applyCustomPreset(preset)
                                                    }
                                                    .buttonStyle(.bordered)
                                                    .controlSize(.small)
                                                    .tint(activeCustomPreset?.id == preset.id ? .accentColor : .secondary)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .fill(activeCustomPreset?.id == preset.id
                                                                  ? Color.accentColor.opacity(0.12)
                                                                  : Color.clear)
                                                    )
                                                    .help(preset.summary)

                                                    Button {
                                                        presetStore.delete(preset)
                                                        if activeCustomPreset?.id == preset.id {
                                                            activeCustomPreset = nil
                                                        }
                                                    } label: {
                                                        Image(systemName: "xmark")
                                                            .font(.system(size: 8, weight: .bold))
                                                    }
                                                    .buttonStyle(.borderless)
                                                    .foregroundColor(.secondary)
                                                    .help("Delete \"\(preset.name)\"")
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Platform note
                            if let note = platformPreset.note {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(note)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }

                            // XHS duration warning
                            if platformPreset == .xiaohongshu,
                               let maxDur = platformPreset.maxDuration,
                               (endTime - startTime) > maxDur {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("当前片段 \(String(format: "%.1f", endTime - startTime))s 超过 2.8s，小红书 Live Photo 动效可能不触发")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    Spacer()
                                    Button("自动裁剪") {
                                        endTime = min(startTime + maxDur, processor.duration)
                                        if coverTime > endTime { coverTime = endTime }
                                    }
                                    .controlSize(.mini)
                                    .buttonStyle(.bordered)
                                    .tint(.orange)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.orange.opacity(0.08)))
                            }

                            // ── Codec ─────────────────────────────────────────
                            settingsRow(label: "Codec") {
                                ForEach(ExportCodec.allCases) { c in
                                    settingButton(c.rawValue, selected: exportSettings.codec == c) {
                                        exportSettings.codec = c
                                        if c == .h264 { exportSettings.exportHDR = false }
                                        platformPreset = .custom; activeCustomPreset = nil
                                    }
                                }
                                Text(exportSettings.codec.note)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            // ── Resolution ────────────────────────────────────
                            settingsRow(label: "Resolution") {
                                ForEach(ExportResolution.allCases) { r in
                                    settingButton(r.rawValue, selected: exportSettings.resolution == r) {
                                        exportSettings.resolution = r
                                        platformPreset = .custom; activeCustomPreset = nil
                                    }
                                }
                            }

                            // ── Quality ───────────────────────────────────────
                            settingsRow(label: "Quality") {
                                ForEach(ExportQuality.allCases) { q in
                                    settingButton(q.rawValue, selected: exportSettings.quality == q) {
                                        exportSettings.quality = q
                                        platformPreset = .custom; activeCustomPreset = nil
                                    }
                                }
                                let mbps = exportSettings.quality.approxMbps(
                                    codec: exportSettings.codec,
                                    resolution: exportSettings.resolution
                                )
                                if !mbps.isEmpty {
                                    Text(mbps)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                                }
                            }

                            // ── Frame Rate ────────────────────────────────────
                            settingsRow(label: "Frame Rate") {
                                ForEach(ExportFrameRate.allCases) { f in
                                    settingButton(f.rawValue, selected: exportSettings.frameRate == f) {
                                        exportSettings.frameRate = f
                                        platformPreset = .custom; activeCustomPreset = nil
                                    }
                                }
                                Text("AVAssetExportSession preserves source fps; selection is informational")
                                    .font(.caption2)
                                    .foregroundColor(Color.secondary.opacity(0.6))
                            }

                            // ── HDR (only if source is HDR) ───────────────────
                            if processor.isHDR {
                                settingsRow(label: "HDR") {
                                    Toggle(isOn: Binding(
                                        get: { exportSettings.exportHDR },
                                        set: { v in
                                            exportSettings.exportHDR = v
                                            if v && exportSettings.codec == .h264 {
                                                exportSettings.codec = .hevc
                                            }
                                            platformPreset = .custom; activeCustomPreset = nil
                                        }
                                    )) {
                                        Text("Export HDR")
                                    }
                                    .toggleStyle(.checkbox)
                                    Text(exportSettings.exportHDR
                                         ? "HEVC / H.265 — HLG color space preserved"
                                         : "H.264 — tone-mapped to SDR")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Loop preview + seek controls
                            HStack(spacing: 16) {
                                // Loop Preview toggle
                                Toggle(isOn: $isLoopPreview) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "repeat")
                                        Text("Loop Preview")
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .help("Loop playback within the selected clip range")
                                .onChange(of: isLoopPreview) { on in
                                    if on { startLoopPreview() } else { stopLoopPreview() }
                                }
                                .onChange(of: startTime) { _ in
                                    if isLoopPreview { startLoopPreview() }
                                }
                                .onChange(of: endTime) { _ in
                                    if isLoopPreview { startLoopPreview() }
                                }

                                if isLoopPreview {
                                    Text("\(formatTime(startTime)) – \(formatTime(endTime))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }

                                Spacer()

                                Button("Seek to Cover") {
                                    let t = CMTime(seconds: coverTime, preferredTimescale: 600)
                                    player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
                                }
                                .controlSize(.small)

                                Button("Open Different Video") {
                                    openVideoFile()
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal)

                        Divider()

                        // Export section
                        VStack(spacing: 8) {
                            if processor.isProcessing {
                                ProgressView(value: processor.progress) {
                                    Text(processor.statusMessage)
                                        .font(.caption)
                                }
                                .padding(.horizontal)
                            }

                            HStack(spacing: 12) {
                                Button(action: exportLivePhoto) {
                                    Label("Create Live Photo", systemImage: "livephoto")
                                        .frame(minWidth: 160)
                                }
                                .controlSize(.large)
                                .buttonStyle(.borderedProminent)
                                .disabled(processor.isProcessing)

                                Button(action: exportAndImportToPhotos) {
                                    Label("Save to Photos", systemImage: "photo.on.rectangle.angled")
                                        .frame(minWidth: 160)
                                }
                                .controlSize(.large)
                                .buttonStyle(.bordered)
                                .disabled(processor.isProcessing)
                            }

                            if !processor.statusMessage.isEmpty && !processor.isProcessing {
                                Text(processor.statusMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                    }
                }
            } else {
                // Drop zone
                dropZoneView
            }
        }
    }   // end mainEditingArea

    // ── Reusable settings row ──────────────────────────────────────────────────
    @ViewBuilder
    private func settingsRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label + ":")
                .font(.subheadline)
                .frame(width: 85, alignment: .trailing)
                .foregroundColor(.secondary)
            content()
            Spacer()
        }
    }

    private func settingButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(selected ? .accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
    }

    private var dropZoneView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "video.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(isDragOver ? .accentColor : .secondary)

            Text("Drop a video file here")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("or")
                .foregroundColor(.secondary)

            Button("Open Video") {
                openVideoFile()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Text("Supports MOV, MP4, M4V — including HDR (HLG/PQ)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDragOver ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .padding()
        )
    }

    private func openVideoFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType.movie, UTType.mpeg4Movie, UTType.quickTimeMovie,
            UTType(filenameExtension: "m4v") ?? .movie,
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            for url in panel.urls { addToQueue(url) }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let supported = ["mov", "mp4", "m4v", "avi", "mkv"]
        var anyHandled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url  = URL(dataRepresentation: data, relativeTo: nil),
                      supported.contains(url.pathExtension.lowercased()) else { return }
                Task { @MainActor in addToQueue(url) }
            }
            anyHandled = true
        }
        return anyHandled
    }

    // ── File queue management ──────────────────────────────────────────────────

    private func addToQueue(_ url: URL) {
        if let existing = fileQueue.firstIndex(where: { $0.url == url }) {
            switchToFile(at: existing); return
        }
        fileQueue.append(FileQueueItem(url: url))
        switchToFile(at: fileQueue.count - 1)
    }

    private func switchToFile(at index: Int) {
        guard index >= 0, index < fileQueue.count else { return }
        currentQueueIndex = index
        loadVideoContent(url: fileQueue[index].url)
    }

    // ── Platform preset ────────────────────────────────────────────────────────

    private func applyPlatformPreset(_ preset: PlatformPreset) {
        platformPreset = preset
        if preset != .custom {
            exportSettings = preset.recommended
        }
        activeCustomPreset = nil
    }

    // ── Custom preset save / load ──────────────────────────────────────────────

    private func commitSavePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let p = SavedPreset(name: name, settings: exportSettings, platform: platformPreset)
        presetStore.add(p)
        activeCustomPreset = p
        newPresetName = ""
        showingSaveField = false
    }

    private func applyCustomPreset(_ preset: SavedPreset) {
        activeCustomPreset = preset
        platformPreset = preset.platform
        exportSettings = preset.settings
    }

    // ── Loop preview ───────────────────────────────────────────────────────────

    private func startLoopPreview() {
        guard let player = player else { return }
        if let obs = loopObserver { player.removeTimeObserver(obs); loopObserver = nil }

        let startCM = CMTime(seconds: startTime, preferredTimescale: 600)
        let endCM   = CMTime(seconds: max(endTime, startTime + 0.05), preferredTimescale: 600)

        player.seek(to: startCM, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            player.play()
        }

        let capturedStart = startTime
        loopObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: endCM)],
            queue: .main
        ) { [weak player] in
            let s = CMTime(seconds: capturedStart, preferredTimescale: 600)
            player?.seek(to: s, toleranceBefore: .zero, toleranceAfter: .zero)
            player?.play()
        }
    }

    private func stopLoopPreview() {
        if let obs = loopObserver { player?.removeTimeObserver(obs); loopObserver = nil }
        player?.pause()
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", mins, secs, frac)
    }

    // ── Load video content (called by queue switch) ────────────────────────────

    private func loadVideoContent(url: URL) {
        stopLoopPreview()
        isLoopPreview = false
        exportSettings = ExportSettings()
        exportSettings.exportHDR = false
        platformPreset = .custom
        activeCustomPreset = nil
        videoURL = url
        coverFramePreview = nil
        coverPreviewTask?.cancel()
        let avAsset = AVAsset(url: url)
        asset = avAsset
        player = AVPlayer(url: url)
        player?.pause()

        Task {
            _ = await processor.loadAsset(url: url)
            exportSettings.exportHDR = processor.isHDR
            let totalDuration = processor.duration
            startTime = 0
            endTime = min(totalDuration, 3.0)
            coverTime = 0
            thumbnails = await ThumbnailGenerator.generateThumbnails(asset: avAsset)
        }
    }

    private func exportLivePhoto() {
        guard let asset = asset else { return }

        Task {
            do {
                processor.isProcessing = true
                processor.statusMessage = "Extracting cover frame..."
                processor.progress = 0

                let coverCMTime = CMTime(seconds: coverTime, preferredTimescale: 600)
                let cgImage = try await processor.extractCoverFrame(asset: asset, at: coverCMTime)

                processor.statusMessage = "Exporting video clip..."
                processor.progress = 0.1

                let startCMTime = CMTime(seconds: startTime, preferredTimescale: 600)
                let endCMTime = CMTime(seconds: endTime, preferredTimescale: 600)
                let exportedVideoURL = try await processor.exportVideo(
                    asset: asset,
                    startTime: startCMTime,
                    endTime: endCMTime,
                    settings: exportSettings
                )

                processor.statusMessage = "Creating Live Photo pair..."
                processor.progress = 0.9

                let openPanel = NSOpenPanel()
                openPanel.title = "Choose Save Location"
                openPanel.message = "Select a folder to save the Live Photo files"
                openPanel.canChooseFiles = false
                openPanel.canChooseDirectories = true
                openPanel.canCreateDirectories = true

                guard openPanel.runModal() == .OK, let saveDir = openPanel.url else {
                    processor.isProcessing = false
                    processor.statusMessage = "Export cancelled."
                    return
                }

                let creator = LivePhotoCreator()
                let result = try await creator.createLivePhoto(
                    coverImage: cgImage,
                    videoURL: exportedVideoURL,
                    outputDirectory: saveDir
                )

                try? FileManager.default.removeItem(at: exportedVideoURL)

                processor.isProcessing = false
                processor.progress = 1.0
                processor.statusMessage = "Live Photo saved! Image: \(result.imageURL.lastPathComponent), Video: \(result.videoURL.lastPathComponent)"

                NSWorkspace.shared.selectFile(result.imageURL.path, inFileViewerRootedAtPath: saveDir.path)

            } catch {
                processor.isProcessing = false
                processor.statusMessage = ""
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func exportAndImportToPhotos() {
        guard let asset = asset else { return }

        Task {
            do {
                processor.isProcessing = true
                processor.statusMessage = "Extracting cover frame..."
                processor.progress = 0

                let coverCMTime = CMTime(seconds: coverTime, preferredTimescale: 600)
                let cgImage = try await processor.extractCoverFrame(asset: asset, at: coverCMTime)

                processor.statusMessage = "Exporting video clip..."
                processor.progress = 0.1

                let startCMTime = CMTime(seconds: startTime, preferredTimescale: 600)
                let endCMTime = CMTime(seconds: endTime, preferredTimescale: 600)
                let exportedVideoURL = try await processor.exportVideo(
                    asset: asset,
                    startTime: startCMTime,
                    endTime: endCMTime,
                    settings: exportSettings
                )

                processor.statusMessage = "Creating Live Photo pair..."
                processor.progress = 0.85

                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("LivePhotoMaker_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                let creator = LivePhotoCreator()
                let result = try await creator.createLivePhoto(
                    coverImage: cgImage,
                    videoURL: exportedVideoURL,
                    outputDirectory: tempDir
                )

                processor.statusMessage = "Importing to Photos..."
                processor.progress = 0.95

                try await creator.importToPhotos(imageURL: result.imageURL, videoURL: result.videoURL)

                try? FileManager.default.removeItem(at: tempDir)
                try? FileManager.default.removeItem(at: exportedVideoURL)

                processor.isProcessing = false
                processor.progress = 1.0
                processor.statusMessage = "Live Photo saved to Photos app!"

            } catch {
                processor.isProcessing = false
                processor.statusMessage = ""
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
