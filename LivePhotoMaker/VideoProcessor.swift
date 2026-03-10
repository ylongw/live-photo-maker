import AVFoundation
import CoreImage
import CoreVideo
import AppKit
import UniformTypeIdentifiers

enum ExportCodec: String, CaseIterable, Identifiable, Codable {
    case h264 = "H.264"
    case hevc = "H.265 HEVC"

    var id: String { rawValue }

    var note: String {
        self == .h264
            ? L10n.shared.codecH264Note
            : L10n.shared.codecHevcNote
    }
}

enum ExportResolution: String, CaseIterable, Identifiable, Codable {
    case p720 = "720p"
    case p1080 = "1080p"
    case p2160 = "4K"
    case source = "Source"

    var id: String { rawValue }
}

enum ExportQuality: String, CaseIterable, Identifiable, Codable {
    case low = "Low"
    case high = "High"
    case source = "Source"

    var id: String { rawValue }

    func approxMbps(codec: ExportCodec, resolution: ExportResolution) -> String {
        if self == .source { return "original" }

        switch (codec, resolution, self) {
        case (.h264, .p720, .low): return "~2 Mbps"
        case (.h264, .p720, .high): return "~6 Mbps"
        case (.h264, .p1080, .low): return "~5 Mbps"
        case (.h264, .p1080, .high): return "~16 Mbps"
        case (.h264, .p2160, _): return "~25 Mbps"
        case (.hevc, .p720, .low): return "~2 Mbps"
        case (.hevc, .p720, .high): return "~4 Mbps"
        case (.hevc, .p1080, .low): return "~3 Mbps"
        case (.hevc, .p1080, .high): return "~8 Mbps"
        case (.hevc, .p2160, _): return "~15 Mbps"
        default: return ""
        }
    }
}

enum ExportFrameRate: String, CaseIterable, Identifiable, Codable {
    case fps24 = "24"
    case fps30 = "30"
    case fps60 = "60"
    case source = "Source"

    var id: String { rawValue }
}

struct ExportSettings: Codable, Equatable {
    var codec: ExportCodec = .h264
    var resolution: ExportResolution = .source
    var quality: ExportQuality = .high
    var frameRate: ExportFrameRate = .source
    var exportHDR: Bool = false
    var muteAudio: Bool = false
}

enum PlatformPreset: String, CaseIterable, Identifiable, Codable {
    case custom = "Custom"
    case xiaohongshu = "小红书 XHS"
    case douyin = "抖音"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .custom:      return L10n.shared.presetCustom
        case .xiaohongshu: return "🍠 小红书"
        case .douyin:      return "🎵 抖音"
        }
    }

    var recommended: ExportSettings {
        switch self {
        case .custom:
            return ExportSettings()
        case .xiaohongshu:
            return ExportSettings(codec: .h264, resolution: .p720, quality: .low, frameRate: .source, exportHDR: false)
        case .douyin:
            return ExportSettings(codec: .h264, resolution: .p1080, quality: .low, frameRate: .source, exportHDR: false)
        }
    }

    var note: String? {
        switch self {
        case .xiaohongshu:
            return "推荐值：H.264 · 720p · Low · SDR。可自行调整后保存为 Custom Preset"
        case .douyin:
            return "推荐值：H.264 · 1080p · Low · SDR。⚠️ 抖音图片帖不支持 Live Photo 动效"
        case .custom:
            return nil
        }
    }

    var maxDuration: Double? {
        self == .xiaohongshu ? 2.8 : nil
    }
}

@MainActor
class VideoProcessor: ObservableObject {
    @Published var isHDR = false
    @Published var duration: Double = 0
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var isProcessing = false

    private var hdrTransferFunction: CFString?

    func loadAsset(url: URL) async -> AVAsset {
        let asset = AVAsset(url: url)
        do {
            let dur = try await asset.load(.duration)
            self.duration = CMTimeGetSeconds(dur)
            let detected = await detectHDR(asset: asset)
            self.isHDR = detected
        } catch {
            statusMessage = "Failed to load video: \(error.localizedDescription)"
        }
        return asset
    }

    func detectHDR(asset: AVAsset) async -> Bool {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return false }
            let descriptions = try await track.load(.formatDescriptions)
            for desc in descriptions {
                let formatDesc = desc as CMFormatDescription
                if let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] {
                    if let tf = extensions[kCVImageBufferTransferFunctionKey as String] as? String {
                        let hlg = kCVImageBufferTransferFunction_ITU_R_2100_HLG as String
                        let pq = kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String
                        if tf == hlg || tf == pq {
                            hdrTransferFunction = tf as CFString
                            return true
                        }
                    }
                }
            }
        } catch {
            statusMessage = "Could not detect HDR: \(error.localizedDescription)"
        }
        return false
    }

    /// - Parameter exportHDR: When true, preserves HLG/PQ dynamic range in the returned CGImage.
    ///   When false (SDR export), lets AVAssetImageGenerator apply the built-in tone-map so the
    ///   cover frame matches the SDR video's visual appearance.
    func extractCoverFrame(asset: AVAsset, at time: CMTime, exportHDR: Bool = false) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if exportHDR, #available(macOS 15.0, *) {
            // Match the source dynamic range: returns an HLG/PQ CGImage for HDR sources.
            // Note: Photos.app's still-image renderer uses Apple Adaptive HDR (gain maps) for
            // full EDR brightness; a plain HLG HEIC without a gain map may appear slightly
            // different from the HDR video component. For SDR export, tone-map to match the video.
            generator.dynamicRangePolicy = .matchSource
        }
        // When exportHDR=false (or macOS < 15), AVAssetImageGenerator returns a tone-mapped
        // SDR CGImage in sRGB — consistent with the SDR-exported MOV.
        let (cgImage, _) = try await generator.image(at: time)
        return cgImage
    }

    func saveCoverImage(_ cgImage: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw LivePhotoError.failedToCreateImageDestination
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        if !CGImageDestinationFinalize(destination) {
            throw LivePhotoError.failedToWriteImage
        }
    }

    func exportVideo(
        asset: AVAsset,
        startTime: CMTime,
        endTime: CMTime,
        settings: ExportSettings
    ) async throws -> URL {
        isProcessing = true
        progress = 0
        statusMessage = L10n.shared.statusExportingVideo

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let presetName = resolveAVPreset(settings: settings)

        try await exportWithExportSession(
            asset: asset,
            startTime: startTime,
            endTime: endTime,
            presetName: presetName,
            outputURL: outputURL,
            muteAudio: settings.muteAudio
        )

        isProcessing = false
        progress = 1.0
        statusMessage = L10n.shared.statusExportComplete
        return outputURL
    }

    private func resolveAVPreset(settings: ExportSettings) -> String {
        if settings.quality == .source || settings.resolution == .source {
            return AVAssetExportPresetPassthrough
        }

        let hdr = isHDR && settings.exportHDR

        switch (settings.codec, settings.resolution) {
        case (.hevc, .p1080):
            return hdr ? AVAssetExportPresetHEVC1920x1080 : AVAssetExportPreset1920x1080
        case (.hevc, .p2160):
            return hdr ? AVAssetExportPresetHEVC3840x2160 : AVAssetExportPreset3840x2160
        case (.hevc, .p720):
            return AVAssetExportPreset1280x720
        case (.h264, .p720):
            return AVAssetExportPreset1280x720
        case (.h264, .p1080):
            return settings.quality == .low ? AVAssetExportPreset1920x1080 : AVAssetExportPresetHighestQuality
        case (.h264, .p2160):
            return AVAssetExportPreset3840x2160
        default:
            return AVAssetExportPresetHighestQuality
        }
    }

    private func exportWithExportSession(
        asset: AVAsset,
        startTime: CMTime,
        endTime: CMTime,
        presetName: String,
        outputURL: URL,
        muteAudio: Bool = false
    ) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw LivePhotoError.exportSessionCreationFailed
        }

        session.outputURL = outputURL
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = false
        session.timeRange = CMTimeRange(start: startTime, end: endTime)

        // Mute audio: set all audio track volumes to 0 via AVAudioMix.
        // The audio track is still present but silent (no re-encode needed).
        if muteAudio {
            let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            if !audioTracks.isEmpty {
                let params: [AVMutableAudioMixInputParameters] = audioTracks.map { track in
                    let p = AVMutableAudioMixInputParameters(track: track)
                    p.setVolume(0, at: .zero)
                    return p
                }
                let mix = AVMutableAudioMix()
                mix.inputParameters = params
                session.audioMix = mix
            }
        }

        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.progress = Double(session.progress)
            }
        }

        await session.export()
        progressTimer.invalidate()

        if let error = session.error { throw error }

        guard session.status == .completed else {
            throw LivePhotoError.exportFailed(session.status.rawValue)
        }
    }
}

enum LivePhotoError: LocalizedError {
    case failedToCreateImageDestination
    case failedToWriteImage
    case exportSessionCreationFailed
    case exportFailed(Int)
    case noVideoTrack
    case failedToWriteMetadata
    case contentIdentifierWriteFailed

    var errorDescription: String? {
        switch self {
        case .failedToCreateImageDestination: return "Failed to create image destination for HEIC."
        case .failedToWriteImage:             return "Failed to write cover image."
        case .exportSessionCreationFailed:    return "Failed to create export session."
        case .exportFailed(let s):            return "Export failed with status \(s)."
        case .noVideoTrack:                   return "No video track found in asset."
        case .failedToWriteMetadata:          return "Failed to write metadata."
        case .contentIdentifierWriteFailed:   return "Failed to write content identifier."
        }
    }
}
