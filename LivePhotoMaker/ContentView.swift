import SwiftUI
import AVKit
import AVFoundation
import AppKit
import UniformTypeIdentifiers

// ── Helpers for Liquid Glass ──────────────────────────────────────────────────

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 12

    init(cornerRadius: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

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
    @State private var player:   AVPlayer?
    @State private var asset:    AVAsset?
    @State private var videoURL: URL?

    // ── File queue ───────────────────────────────────────────────────────────
    @State private var fileQueue:         [FileQueueItem] = []
    @State private var currentQueueIndex: Int             = -1

    // ── Timeline state ───────────────────────────────────────────────────────
    @State private var coverTime: Double = 0
    @State private var startTime: Double = 0
    @State private var endTime:   Double = 0
    @State private var thumbnails: [NSImage] = []

    // ── Export settings ──────────────────────────────────────────────────────
    @State private var exportSettings = ExportSettings()
    @State private var platformPreset: PlatformPreset = .custom

    // ── Custom preset store ──────────────────────────────────────────────────
    @StateObject private var presetStore     = PresetStore()
    @State private var activeCustomPreset:   SavedPreset? = nil
    @State private var showingSaveField      = false
    @State private var newPresetName         = ""

    // ── UI state ─────────────────────────────────────────────────────────────
    @State private var isDragOver    = false
    @State private var showError     = false
    @State private var errorMessage  = ""

    @State private var coverFramePreview: NSImage?
    @State private var coverPreviewTask:  Task<Void, Never>?
    @State private var isLoopPreview = false
    @State private var loopObserver: Any? = nil

    var body: some View {
        ZStack {
            // Window-level blur background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                if !fileQueue.isEmpty {
                    fileSidebarView
                    Divider().opacity(0.2)
                }
                mainEditingArea
            }
        }
        .frame(minWidth: fileQueue.isEmpty ? 800 : 1000, minHeight: 700)
        .alert("Error", isPresented: $showError) { Button("OK") {} } message: { Text(errorMessage) }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { handleDrop(providers: $0) }
    }

    // ── Sidebar ───────────────────────────────────────────────────────────────
    private var fileSidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FILES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: openVideoFile) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 14))
                }.buttonStyle(.plain).help("Add more videos")
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(fileQueue.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 10) {
                            Image(systemName: index == currentQueueIndex ? "play.circle.fill" : "film")
                                .foregroundColor(index == currentQueueIndex ? .accentColor : .secondary)
                                .font(.system(size: 13))
                            Text(item.name)
                                .font(.system(size: 12, weight: index == currentQueueIndex ? .medium : .regular))
                                .lineLimit(1).truncationMode(.middle)
                                .foregroundColor(index == currentQueueIndex ? .primary : .secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(index == currentQueueIndex ? Color.accentColor.opacity(0.18) : Color.clear))
                        .contentShape(Rectangle())
                        .onTapGesture { switchToFile(at: index) }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(width: 200)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        .overlay(Rectangle().fill(.secondary.opacity(0.2)).frame(width: 0.5), alignment: .trailing)
    }

    // ── Main editing area ──────────────────────────────────────────────────────
    private var mainEditingArea: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("LivePhotoMaker")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                if let url = videoURL {
                    Text(url.lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
                }
                Spacer()
                if processor.isHDR {
                    Label("HDR", systemImage: "sparkles.tv")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)

            if let player = player {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Video preview
                            GlassCard(cornerRadius: 16) {
                                VideoPlayerView(player: player)
                                    .frame(minHeight: 420, maxHeight: 620)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .padding(.horizontal, 24)

                            // Timeline
                            GlassCard {
                                TimelineView(
                                    duration: processor.duration,
                                    coverTime: $coverTime,
                                    startTime: $startTime,
                                    endTime:   $endTime,
                                    thumbnails: thumbnails,
                                    coverFramePreview: coverFramePreview
                                )
                                .padding(.top, coverFramePreview != nil ? 60 : 0)
                            }
                            .padding(.horizontal, 24)
                            .onChange(of: coverTime) { newTime in
                                updateCoverPreview(at: newTime)
                            }

                            // Controls
                            VStack(spacing: 12) {
                                // Presets
                                GlassCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(spacing: 8) {
                                            Text("Optimized for:")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.secondary)
                                            ForEach(PlatformPreset.allCases) { preset in
                                                presetButton(preset)
                                            }
                                            Spacer()
                                            savePresetControl
                                        }

                                        if !presetStore.presets.isEmpty {
                                            HStack(spacing: 8) {
                                                Text("My Presets:")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary.opacity(0.7))
                                                ScrollView(.horizontal, showsIndicators: false) {
                                                    HStack(spacing: 6) {
                                                        ForEach(presetStore.presets) { p in
                                                            customPresetChip(p)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        if let note = platformPreset.note {
                                            HStack(spacing: 6) {
                                                Image(systemName: "info.circle").font(.caption)
                                                Text(note).font(.caption)
                                            }
                                            .foregroundColor(.secondary)
                                        }
                                    }
                                }

                                // XHS warning
                                if platformPreset == .xiaohongshu,
                                   let maxDur = platformPreset.maxDuration,
                                   (endTime - startTime) > maxDur {
                                    xhsDurationWarning(maxDur: maxDur)
                                }

                                // Export settings rows
                                VStack(spacing: 8) {
                                    settingsRow(label: "Codec", icon: "video.square") {
                                        ForEach(ExportCodec.allCases) { c in
                                            settingButton(c.rawValue, selected: exportSettings.codec == c) {
                                                exportSettings.codec = c
                                                if c == .h264 { exportSettings.exportHDR = false }
                                                markCustom()
                                            }
                                        }
                                        Text(exportSettings.codec.note)
                                            .font(.caption2).foregroundColor(.secondary)
                                    }

                                    settingsRow(label: "Resolution", icon: "aspectratio") {
                                        ForEach(ExportResolution.allCases) { r in
                                            settingButton(r.rawValue, selected: exportSettings.resolution == r) {
                                                exportSettings.resolution = r; markCustom()
                                            }
                                        }
                                    }

                                    settingsRow(label: "Quality", icon: "slider.horizontal.3") {
                                        ForEach(ExportQuality.allCases) { q in
                                            settingButton(q.rawValue, selected: exportSettings.quality == q) {
                                                exportSettings.quality = q; markCustom()
                                            }
                                        }
                                        let mbps = exportSettings.quality.approxMbps(
                                            codec: exportSettings.codec,
                                            resolution: exportSettings.resolution)
                                        if !mbps.isEmpty {
                                            Text(mbps)
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(.white.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                    }

                                    settingsRow(label: "Frame Rate", icon: "film.stack") {
                                        ForEach(ExportFrameRate.allCases) { f in
                                            settingButton(f.rawValue, selected: exportSettings.frameRate == f) {
                                                exportSettings.frameRate = f; markCustom()
                                            }
                                        }
                                        Text("※ preserves source fps")
                                            .font(.caption2).foregroundColor(.secondary.opacity(0.6))
                                    }

                                    if processor.isHDR {
                                        settingsRow(label: "HDR", icon: "sun.max.fill") {
                                            Toggle(isOn: Binding(
                                                get: { exportSettings.exportHDR },
                                                set: { v in
                                                    exportSettings.exportHDR = v
                                                    if v && exportSettings.codec == .h264 { exportSettings.codec = .hevc }
                                                    markCustom()
                                                }
                                            )) { Text("Export HDR").font(.system(size: 12)) }
                                            .toggleStyle(.checkbox)
                                            Text(exportSettings.exportHDR
                                                 ? "HEVC / H.265 — HLG preserved"
                                                 : "H.264 — tone-mapped to SDR")
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                }

                                // Loop + seek utils
                                HStack(spacing: 16) {
                                    Toggle(isOn: $isLoopPreview) {
                                        Label("Loop Preview", systemImage: "repeat")
                                            .font(.system(size: 12))
                                    }
                                    .toggleStyle(.checkbox)
                                    .onChange(of: isLoopPreview) { on in
                                        if on { startLoopPreview() } else { stopLoopPreview() }
                                    }
                                    .onChange(of: startTime) { _ in if isLoopPreview { startLoopPreview() } }
                                    .onChange(of: endTime)   { _ in if isLoopPreview { startLoopPreview() } }

                                    if isLoopPreview {
                                        Text("\(formatTime(startTime)) – \(formatTime(endTime))")
                                            .font(.caption).foregroundColor(.secondary).monospacedDigit()
                                    }

                                    Spacer()
                                    Button("Seek to Cover") {
                                        let t = CMTime(seconds: coverTime, preferredTimescale: 600)
                                        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
                                    }.buttonStyle(.link).font(.system(size: 11))
                                    Button("Change Video") { openVideoFile() }
                                        .buttonStyle(.link).font(.system(size: 11))
                                }
                                .padding(.top, 4)
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 100) // Space for floating export bar
                        }
                    }

                    // Floating export bar
                    VStack(spacing: 0) {
                        Divider().opacity(0.1)
                        HStack(spacing: 20) {
                            if processor.isProcessing {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: processor.progress)
                                        .progressViewStyle(.linear)
                                        .frame(width: 140)
                                    Text(processor.statusMessage)
                                        .font(.system(size: 10)).foregroundColor(.secondary)
                                }
                            } else if !processor.statusMessage.isEmpty {
                                Text(processor.statusMessage)
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: exportLivePhoto) {
                                Label("Create Live Photo", systemImage: "livephoto")
                                    .frame(width: 148, height: 28)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(processor.isProcessing)

                            Button(action: exportAndImportToPhotos) {
                                Label("Save to Photos", systemImage: "photo.on.rectangle.angled")
                                    .frame(width: 148, height: 28)
                            }
                            .buttonStyle(.bordered).controlSize(.large)
                            .disabled(processor.isProcessing)
                        }
                        .padding(.horizontal, 32)
                        .frame(height: 76)
                    }
                    .background(.ultraThinMaterial)
                    .overlay(Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5), alignment: .top)
                }
            } else {
                dropZoneView
            }
        }
    }

    // ── Drop zone ──────────────────────────────────────────────────────────────
    private var dropZoneView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(isDragOver ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.05))
                    .frame(width: 120, height: 120)
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(isDragOver ? .accentColor : .secondary)
            }
            VStack(spacing: 8) {
                Text("Drop video here")
                    .font(.system(size: 20, weight: .semibold))
                Text("MOV, MP4, M4V · HDR supported")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Button("Select File") { openVideoFile() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(isDragOver ? Color.accentColor : Color.secondary.opacity(0.2),
                                      style: StrokeStyle(lineWidth: 2, dash: [6]))
                )
                .padding(40)
        )
    }

    // ── Reusable component builders ────────────────────────────────────────────

    @ViewBuilder
    private func settingsRow<Content: View>(label: String, icon: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        GlassCard(cornerRadius: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.secondary).frame(width: 18)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 72, alignment: .leading)
                content()
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    private func settingButton(_ title: String, selected: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(selected ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func presetButton(_ preset: PlatformPreset) -> some View {
        let isSelected = platformPreset == preset && activeCustomPreset == nil
        return Button(preset.label) { applyPlatformPreset(preset) }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.05))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.4) : .white.opacity(0.05), lineWidth: 0.5))
            .font(.system(size: 11, weight: .medium))
    }

    private func customPresetChip(_ preset: SavedPreset) -> some View {
        let isSelected = activeCustomPreset?.id == preset.id
        return HStack(spacing: 4) {
            Button(preset.name) { applyCustomPreset(preset) }.buttonStyle(.plain)
            Button {
                presetStore.delete(preset)
                if isSelected { activeCustomPreset = nil }
            } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 10))
            }
            .buttonStyle(.plain).foregroundColor(.secondary.opacity(0.5))
        }
        .font(.system(size: 10))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.05))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.4) : .white.opacity(0.05), lineWidth: 0.5))
    }

    @ViewBuilder
    private var savePresetControl: some View {
        if showingSaveField {
            HStack(spacing: 6) {
                TextField("Name...", text: $newPresetName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 110)
                    .onSubmit { commitSavePreset() }
                Button("Save") { commitSavePreset() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("✕") { showingSaveField = false; newPresetName = "" }
                    .buttonStyle(.plain).foregroundColor(.secondary).font(.system(size: 11))
            }
        } else {
            Button { showingSaveField = true } label: {
                Image(systemName: "square.and.arrow.down").font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Save current export settings as a named preset")
        }
    }

    private func xhsDurationWarning(maxDur: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange).font(.system(size: 13))
            Text("片段 \(String(format: "%.1f", endTime - startTime))s 超过 \(String(format: "%.1f", maxDur))s，小红书 Live Photo 动效可能失效")
                .font(.system(size: 11, weight: .medium)).foregroundColor(.orange)
            Spacer()
            Button("自动裁剪") {
                endTime = min(startTime + maxDur, processor.duration)
                if coverTime > endTime { coverTime = endTime }
            }
            .buttonStyle(.bordered).tint(.orange).controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.2), lineWidth: 0.5))
    }

    // ── Logic helpers ──────────────────────────────────────────────────────────

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", mins, secs, frac)
    }

    private func updateCoverPreview(at time: Double) {
        coverPreviewTask?.cancel()
        coverPreviewTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let asset = asset else { return }
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            if let cg = try? await processor.extractCoverFrame(asset: asset, at: cmTime, exportHDR: exportSettings.exportHDR) {
                coverFramePreview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
    }

    private func markCustom() { platformPreset = .custom; activeCustomPreset = nil }

    private func applyPlatformPreset(_ preset: PlatformPreset) {
        platformPreset = preset; activeCustomPreset = nil
        if preset != .custom {
            exportSettings = preset.recommended
            if !processor.isHDR { exportSettings.exportHDR = false }
        }
    }

    private func applyCustomPreset(_ preset: SavedPreset) {
        activeCustomPreset = preset; platformPreset = preset.platform; exportSettings = preset.settings
    }

    private func commitSavePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let p = SavedPreset(name: name, settings: exportSettings, platform: platformPreset)
        presetStore.add(p); activeCustomPreset = p; newPresetName = ""; showingSaveField = false
    }

    private func startLoopPreview() {
        guard let player = player else { return }
        if let obs = loopObserver { player.removeTimeObserver(obs); loopObserver = nil }
        let startCM = CMTime(seconds: startTime, preferredTimescale: 600)
        let endCM   = CMTime(seconds: max(endTime, startTime + 0.05), preferredTimescale: 600)
        player.seek(to: startCM, toleranceBefore: .zero, toleranceAfter: .zero) { _ in player.play() }
        let capturedStart = startTime
        loopObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: endCM)], queue: .main) { [weak player] in
            player?.seek(to: CMTime(seconds: capturedStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            player?.play()
        }
    }

    private func stopLoopPreview() {
        if let obs = loopObserver { player?.removeTimeObserver(obs); loopObserver = nil }
        player?.pause()
    }

    private func openVideoFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie,
                                     UTType(filenameExtension: "m4v") ?? .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories    = false
        if panel.runModal() == .OK { panel.urls.forEach { addToQueue($0) } }
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

    private func loadVideoContent(url: URL) {
        stopLoopPreview(); isLoopPreview = false; platformPreset = .custom
        exportSettings = ExportSettings(); activeCustomPreset = nil
        videoURL = url; coverFramePreview = nil; coverPreviewTask?.cancel()
        let avAsset = AVAsset(url: url)
        asset = avAsset; player = AVPlayer(url: url); player?.pause()
        Task {
            _ = await processor.loadAsset(url: url)
            exportSettings.exportHDR = processor.isHDR
            if processor.isHDR { exportSettings.codec = .hevc }
            startTime = 0; endTime = min(processor.duration, 3.0); coverTime = 0
            thumbnails = await ThumbnailGenerator.generateThumbnails(asset: avAsset)
        }
    }

    // ── Export ─────────────────────────────────────────────────────────────────

    private func exportLivePhoto() {
        guard let asset = asset else { return }
        Task {
            do {
                processor.isProcessing = true; processor.statusMessage = "Extracting cover…"; processor.progress = 0
                let coverCM = CMTime(seconds: coverTime, preferredTimescale: 600)
                let cgImage = try await processor.extractCoverFrame(asset: asset, at: coverCM, exportHDR: exportSettings.exportHDR)
                processor.statusMessage = "Exporting video clip…"; processor.progress = 0.1
                let exportedURL = try await processor.exportVideo(
                    asset: asset,
                    startTime: CMTime(seconds: startTime, preferredTimescale: 600),
                    endTime:   CMTime(seconds: endTime,   preferredTimescale: 600),
                    settings: exportSettings)

                let openPanel = NSOpenPanel()
                openPanel.title = "Choose Save Location"
                openPanel.canChooseFiles = false; openPanel.canChooseDirectories = true; openPanel.canCreateDirectories = true
                guard openPanel.runModal() == .OK, let saveDir = openPanel.url else {
                    processor.isProcessing = false; processor.statusMessage = "Export cancelled."; return
                }
                let creator = LivePhotoCreator()
                let result  = try await creator.createLivePhoto(coverImage: cgImage, videoURL: exportedURL, outputDirectory: saveDir)
                try? FileManager.default.removeItem(at: exportedURL)
                processor.isProcessing = false; processor.progress = 1.0
                processor.statusMessage = "Saved! \(result.imageURL.lastPathComponent) + \(result.videoURL.lastPathComponent)"
                NSWorkspace.shared.selectFile(result.imageURL.path, inFileViewerRootedAtPath: saveDir.path)
            } catch {
                processor.isProcessing = false; processor.statusMessage = ""
                errorMessage = error.localizedDescription; showError = true
            }
        }
    }

    private func exportAndImportToPhotos() {
        guard let asset = asset else { return }
        Task {
            do {
                processor.isProcessing = true; processor.statusMessage = "Preparing Live Photo…"; processor.progress = 0
                let coverCM = CMTime(seconds: coverTime, preferredTimescale: 600)
                let cgImage = try await processor.extractCoverFrame(asset: asset, at: coverCM, exportHDR: exportSettings.exportHDR)
                processor.progress = 0.1
                let exportedURL = try await processor.exportVideo(
                    asset: asset,
                    startTime: CMTime(seconds: startTime, preferredTimescale: 600),
                    endTime:   CMTime(seconds: endTime,   preferredTimescale: 600),
                    settings: exportSettings)
                processor.statusMessage = "Creating Live Photo pair…"; processor.progress = 0.85
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("LivePhotoMaker_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let creator = LivePhotoCreator()
                let result  = try await creator.createLivePhoto(coverImage: cgImage, videoURL: exportedURL, outputDirectory: tempDir)
                processor.statusMessage = "Importing to Photos…"; processor.progress = 0.95
                try await creator.importToPhotos(imageURL: result.imageURL, videoURL: result.videoURL)
                try? FileManager.default.removeItem(at: tempDir)
                try? FileManager.default.removeItem(at: exportedURL)
                processor.isProcessing = false; processor.progress = 1.0
                processor.statusMessage = "Live Photo saved to Photos!"
            } catch {
                processor.isProcessing = false; processor.statusMessage = ""
                errorMessage = error.localizedDescription; showError = true
            }
        }
    }
}
