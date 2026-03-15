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
    @State private var isLoopPreview   = false
    @State private var loopObserver:   Any? = nil
    @State private var isPortraitVideo = false   // auto-detected on video load

    @StateObject private var l10n = L10n.shared

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
        .frame(minWidth: isPortraitVideo
            ? (fileQueue.isEmpty ? 920 : 1120)
            : (fileQueue.isEmpty ? 800 : 1000),
               minHeight: 700)
        .alert("Error", isPresented: $showError) { Button("OK") {} } message: { Text(errorMessage) }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { handleDrop(providers: $0) }
        .environmentObject(l10n)
    }

    // ── Sidebar ───────────────────────────────────────────────────────────────
    private var fileSidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(l10n.filesHeader)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: openVideoFile) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 14))
                }.buttonStyle(.plain).help(l10n.addVideos)
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
                        .contextMenu {
                            Button {
                                removeFromQueue(index: index)
                            } label: {
                                Label(l10n.removeFromList, systemImage: "minus.circle")
                            }
                            Button(role: .destructive) {
                                trashQueueFile(index: index)
                            } label: {
                                Label(l10n.moveToTrash, systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(width: 200)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        .overlay(Rectangle().fill(.secondary.opacity(0.2)).frame(width: 0.5), alignment: .trailing)
        // ⌘⌫ → Move to Trash (Finder-standard shortcut for selected sidebar item)
        .background(
            Group {
                Button("") { trashQueueFile(index: currentQueueIndex) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .opacity(0).allowsHitTesting(false)
            }
            .disabled(currentQueueIndex < 0)
        )
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
                    Label(l10n.hdrBadge, systemImage: "sparkles.tv")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .clipShape(Capsule())
                }
                // Language toggle
                Button { l10n.toggleLanguage() } label: {
                    Text(l10n.langToggleLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .frame(width: 26, height: 20)
                        .padding(.horizontal, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help(l10n.langToggleTooltip)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)

            if let player = player {
                if isPortraitVideo {
                    // ── Portrait: controls left ↔ video right ──────────────────
                    HStack(alignment: .top, spacing: 0) {
                        // Left: scrollable controls + sticky export bar
                        VStack(spacing: 0) {
                            ScrollView {
                                VStack(spacing: 16) {
                                    timelineSection
                                        .padding(.horizontal, 16)
                                    quickControlsSection
                                        .padding(.horizontal, 20)
                                        .padding(.top, -4)
                                    exportSettingsPanel
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 16)
                                }
                                .padding(.vertical, 16)
                            }
                            // Sticky export bar (video always visible on right)
                            Divider().opacity(0.12)
                            exportActionsBar
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .overlay(Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5), alignment: .top)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Divider().opacity(0.2)

                        // Right: portrait video fills height
                        GlassCard(cornerRadius: 16) {
                            VideoPlayerView(player: player)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    // ── Landscape: video top, controls below ────────────────────
                    ZStack(alignment: .bottom) {
                        ScrollView {
                            VStack(spacing: 20) {
                                GlassCard(cornerRadius: 16) {
                                    VideoPlayerView(player: player)
                                        .frame(minHeight: 420, maxHeight: 620)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .padding(.horizontal, 24)

                                timelineSection
                                    .padding(.horizontal, 24)

                                quickControlsSection
                                    .padding(.horizontal, 28)
                                    .padding(.top, -4)

                                exportSettingsPanel
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 100)
                            }
                        }
                        VStack(spacing: 0) {
                            Divider().opacity(0.1)
                            exportActionsBar
                                .padding(.horizontal, 32)
                                .frame(height: 76)
                        }
                        .background(.ultraThinMaterial)
                        .overlay(Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5), alignment: .top)
                    }
                }
            } else {
                dropZoneView
            }
        }
    }

    // ── Shared layout sections (portrait + landscape) ────────────────────────────

    private var timelineSection: some View {
        GlassCard {
            TimelineView(
                duration: processor.duration,
                coverTime: $coverTime,
                startTime: $startTime,
                endTime:   $endTime,
                thumbnails: thumbnails,
                coverFramePreview: coverFramePreview
            )
            .padding(.top, coverFramePreview != nil ? 90 : 0)
        }
        .onChange(of: coverTime) { newTime in updateCoverPreview(at: newTime) }
    }

    private var quickControlsSection: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $isLoopPreview) {
                Label(l10n.loopPreview, systemImage: "repeat").font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            .onChange(of: isLoopPreview) { on in if on { startLoopPreview() } else { stopLoopPreview() } }
            .onChange(of: startTime) { _ in if isLoopPreview { startLoopPreview() } }
            .onChange(of: endTime)   { _ in if isLoopPreview { startLoopPreview() } }
            if isLoopPreview {
                Text("\(formatTime(startTime)) – \(formatTime(endTime))")
                    .font(.caption).foregroundColor(.secondary).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.ultraThinMaterial).clipShape(Capsule())
            }
            Spacer()
            Button {
                let t = CMTime(seconds: coverTime, preferredTimescale: 600)
                self.player?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
            } label: {
                Label(l10n.seekToCover, systemImage: "camera.viewfinder").font(.system(size: 11))
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help(l10n.seekTooltip)
        }
    }

    private var exportSettingsPanel: some View {
        VStack(spacing: 12) {
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
                                    ForEach(presetStore.presets) { p in customPresetChip(p) }
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
            if platformPreset == .xiaohongshu,
               let maxDur = platformPreset.maxDuration,
               (endTime - startTime) > maxDur {
                xhsDurationWarning(maxDur: maxDur)
            }
            VStack(spacing: 8) {
                settingsRow(label: l10n.codecLabel, icon: "video.square") {
                    ForEach(ExportCodec.allCases) { c in
                        settingButton(c.rawValue, selected: exportSettings.codec == c) {
                            exportSettings.codec = c
                            if c == .h264 { exportSettings.exportHDR = false }
                            markCustom()
                        }
                    }
                    Text(exportSettings.codec.note).font(.caption2).foregroundColor(.secondary)
                }
                settingsRow(label: l10n.resolutionLabel, icon: "aspectratio") {
                    ForEach(ExportResolution.allCases) { r in
                        settingButton(r.rawValue, selected: exportSettings.resolution == r) {
                            exportSettings.resolution = r; markCustom()
                        }
                    }
                }
                settingsRow(label: l10n.qualityLabel, icon: "slider.horizontal.3") {
                    ForEach(ExportQuality.allCases) { q in
                        settingButton(q.rawValue, selected: exportSettings.quality == q) {
                            exportSettings.quality = q; markCustom()
                        }
                    }
                    let mbps = exportSettings.quality.approxMbps(
                        codec: exportSettings.codec, resolution: exportSettings.resolution)
                    if !mbps.isEmpty {
                        Text(mbps)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.white.opacity(0.1)).clipShape(Capsule())
                    }
                }
                settingsRow(label: l10n.frameRateLabel, icon: "film.stack") {
                    ForEach(ExportFrameRate.allCases) { f in
                        settingButton(f.rawValue, selected: exportSettings.frameRate == f) {
                            exportSettings.frameRate = f; markCustom()
                        }
                    }
                    Text("※ preserves source fps")
                        .font(.caption2).foregroundColor(.secondary.opacity(0.6))
                }
                if processor.isHDR {
                    settingsRow(label: l10n.hdrLabel, icon: "sun.max.fill") {
                        Toggle(isOn: Binding(
                            get: { exportSettings.exportHDR },
                            set: { v in
                                exportSettings.exportHDR = v
                                if v && exportSettings.codec == .h264 { exportSettings.codec = .hevc }
                                markCustom()
                            }
                        )) { Text(l10n.exportHDR).font(.system(size: 12)) }
                        .toggleStyle(.checkbox)
                        Text(exportSettings.exportHDR
                             ? "HEVC / H.265 — HLG preserved"
                             : "H.264 — tone-mapped to SDR")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }

                settingsRow(label: l10n.audioLabel, icon: "speaker.wave.2") {
                    Toggle(isOn: Binding(
                        get: { exportSettings.muteAudio },
                        set: { v in exportSettings.muteAudio = v; markCustom() }
                    )) { Text(l10n.muteLabel).font(.system(size: 12)) }
                    .toggleStyle(.checkbox)
                    Text(exportSettings.muteAudio ? l10n.muteOnNote : l10n.muteOffNote)
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            HStack {
                Spacer()
                Button(l10n.changeVideo) { openVideoFile() }
                    .buttonStyle(.link).font(.system(size: 11))
            }
        }
    }

    private var exportActionsBar: some View {
        HStack(spacing: 20) {
            if processor.isProcessing {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: processor.progress)
                        .progressViewStyle(.linear).frame(width: 140)
                    Text(processor.statusMessage)
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
            } else if !processor.statusMessage.isEmpty {
                Text(processor.statusMessage)
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: exportLivePhoto) {
                Label(l10n.createLivePhoto, systemImage: "livephoto").frame(width: 148, height: 28)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(processor.isProcessing)
            Button(action: exportAndImportToPhotos) {
                Label(l10n.saveToPhotos, systemImage: "photo.on.rectangle.angled").frame(width: 148, height: 28)
            }
            .buttonStyle(.bordered).controlSize(.large).disabled(processor.isProcessing)
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
                Text(l10n.dropTitle)
                    .font(.system(size: 20, weight: .semibold))
                Text(l10n.dropSubtitle)
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Button(l10n.selectFile) { openVideoFile() }
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
                TextField(l10n.presetNamePlaceholder, text: $newPresetName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 110)
                    .onSubmit { commitSavePreset() }
                Button(l10n.save) { commitSavePreset() }
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
            .help(l10n.savePresetTooltip)
        }
    }

    private func xhsDurationWarning(maxDur: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange).font(.system(size: 13))
            Text(l10n.xhsWarning(cur: endTime - startTime, max: maxDur))
                .font(.system(size: 11, weight: .medium)).foregroundColor(.orange)
            Spacer()
            Button(l10n.autoCrop) {
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

    /// Remove item from queue list (file on disk untouched).
    private func removeFromQueue(index: Int) {
        guard index >= 0, index < fileQueue.count else { return }
        fileQueue.remove(at: index)
        if fileQueue.isEmpty {
            currentQueueIndex = -1
            player = nil; videoURL = nil; asset = nil
        } else {
            let next = min(index, fileQueue.count - 1)
            if currentQueueIndex == index {
                currentQueueIndex = next
                loadVideoContent(url: fileQueue[next].url)
            } else if index < currentQueueIndex {
                currentQueueIndex -= 1
            }
        }
    }

    /// Move the file to macOS Trash, then remove from queue.
    private func trashQueueFile(index: Int) {
        guard index >= 0, index < fileQueue.count else { return }
        let url = fileQueue[index].url
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        removeFromQueue(index: index)
    }

    private func loadVideoContent(url: URL) {
        stopLoopPreview(); isLoopPreview = false; platformPreset = .custom
        // Keep user's codec/resolution/quality/fps/mute settings across file switches.
        // Only reset per-file properties (HDR auto-detect, active preset, cover frame).
        exportSettings.exportHDR = false; activeCustomPreset = nil
        videoURL = url; coverFramePreview = nil; coverPreviewTask?.cancel()
        isPortraitVideo = false   // reset; detect below
        let avAsset = AVAsset(url: url)
        asset = avAsset; player = AVPlayer(url: url); player?.pause()
        Task {
            _ = await processor.loadAsset(url: url)
            exportSettings.exportHDR = processor.isHDR
            if processor.isHDR { exportSettings.codec = .hevc }
            startTime = 0; endTime = min(processor.duration, 3.0); coverTime = 0
            thumbnails = await ThumbnailGenerator.generateThumbnails(asset: avAsset)
            // ── Portrait detection ─────────────────────────────────────────
            if let tracks = try? await avAsset.loadTracks(withMediaType: .video),
               let track = tracks.first,
               let naturalSize = try? await track.load(.naturalSize),
               let transform   = try? await track.load(.preferredTransform) {
                let t = naturalSize.applying(transform)
                isPortraitVideo = abs(t.height) > abs(t.width)
            }
        }
    }

    // ── Export ─────────────────────────────────────────────────────────────────

    private func exportLivePhoto() {
        guard let asset = asset else { return }
        Task {
            do {
                processor.isProcessing = true; processor.statusMessage = l10n.statusExtractingCover; processor.progress = 0
                let coverCM = CMTime(seconds: coverTime, preferredTimescale: 600)
                let cgImage = try await processor.extractCoverFrame(asset: asset, at: coverCM, exportHDR: exportSettings.exportHDR)
                processor.statusMessage = l10n.statusExportingClip; processor.progress = 0.1
                let exportedURL = try await processor.exportVideo(
                    asset: asset,
                    startTime: CMTime(seconds: startTime, preferredTimescale: 600),
                    endTime:   CMTime(seconds: endTime,   preferredTimescale: 600),
                    settings: exportSettings)

                let openPanel = NSOpenPanel()
                openPanel.title = "Choose Save Location"
                openPanel.canChooseFiles = false; openPanel.canChooseDirectories = true; openPanel.canCreateDirectories = true
                guard openPanel.runModal() == .OK, let saveDir = openPanel.url else {
                    processor.isProcessing = false; processor.statusMessage = l10n.statusExportCancelled; return
                }
                let creator = LivePhotoCreator()
                let result  = try await creator.createLivePhoto(coverImage: cgImage, videoURL: exportedURL, outputDirectory: saveDir, coverOffset: coverTime - startTime)
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
                processor.isProcessing = true; processor.statusMessage = l10n.statusExtractingCover; processor.progress = 0
                let coverCM = CMTime(seconds: coverTime, preferredTimescale: 600)
                let cgImage = try await processor.extractCoverFrame(asset: asset, at: coverCM, exportHDR: exportSettings.exportHDR)
                processor.progress = 0.1
                let exportedURL = try await processor.exportVideo(
                    asset: asset,
                    startTime: CMTime(seconds: startTime, preferredTimescale: 600),
                    endTime:   CMTime(seconds: endTime,   preferredTimescale: 600),
                    settings: exportSettings)
                processor.statusMessage = l10n.statusCreatingPair; processor.progress = 0.85
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("LivePhotoMaker_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let creator = LivePhotoCreator()
                let result  = try await creator.createLivePhoto(coverImage: cgImage, videoURL: exportedURL, outputDirectory: tempDir, coverOffset: coverTime - startTime)
                processor.statusMessage = l10n.statusImporting; processor.progress = 0.95
                try await creator.importToPhotos(imageURL: result.imageURL, videoURL: result.videoURL)
                try? FileManager.default.removeItem(at: tempDir)
                try? FileManager.default.removeItem(at: exportedURL)
                processor.isProcessing = false; processor.progress = 1.0
                processor.statusMessage = l10n.statusSavedToPhotos
            } catch {
                processor.isProcessing = false; processor.statusMessage = ""
                errorMessage = error.localizedDescription; showError = true
            }
        }
    }
}
