import AVFoundation
import CoreImage
import CoreVideo
import AppKit
import UniformTypeIdentifiers

// ── Platform export presets ────────────────────────────────────────────────────
/// Platform-specific export presets. Each preset locks codec, resolution, and HDR
/// to the effective ceiling of the target platform so the output isn't over-encoded.
enum PlatformPreset: String, CaseIterable, Identifiable, Codable {
    case custom      = "Custom"
    case xiaohongshu = "小红书 XHS"
    case douyin      = "抖音"

    var id: String { rawValue }

    /// Short flag label for the picker button (nil = use rawValue).
    var label: String {
        switch self {
        case .custom:      return "Custom"
        case .xiaohongshu: return "🍠 小红书"
        case .douyin:      return "🎵 抖音"
        }
    }

    /// Informational footnote shown beneath the controls.
    var note: String? {
        switch self {
        case .xiaohongshu:
            return "H.264 · 720p · 4 Mbps · SDR — XHS re-encodes to ≤4 Mbps; 建议时长 ≤2.8s"
        case .douyin:
            return "H.264 · 1080p · 5 Mbps · SDR — ⚠️ 抖音图片帖不支持 Live Photo 动效，仅封面展示"
        case .custom:
            return nil
        }
    }

    /// Recommended maximum clip duration (seconds). nil = no restriction.
    var maxDuration: Double? {
        switch self {
        case .xiaohongshu: return 2.8
        default: return nil
        }
    }

    /// When true the HDR toggle is force-disabled.
    var forcesSDR: Bool { self != .custom }

    /// BitratePreset to apply when this platform is selected.
    var bitratePreset: BitratePreset {
        switch self {
        case .xiaohongshu: return .xhs720p
        case .douyin:      return .douyin1080p
        case .custom:      return .medium
        }
    }
}

// ── Bitrate presets ────────────────────────────────────────────────────────────
enum BitratePreset: String, CaseIterable, Identifiable, Codable {
    // Platform-specific (only set via PlatformPreset; hidden from normal picker)
    case xhs720p    = "XHS 720p (4 Mbps)"
    case douyin1080p = "Douyin 1080p (5 Mbps)"
    // User-selectable
    case low     = "Low (8 Mbps)"
    case medium  = "Medium (16 Mbps)"
    case high    = "High (32 Mbps)"
    case original = "Original"

    var id: String { rawValue }

    /// Cases shown in the normal bitrate picker (platform cases hidden).
    static var displayCases: [BitratePreset] { [.low, .medium, .high, .original] }

    var bitsPerSecond: Int? {
        switch self {
        case .xhs720p:    return 4_000_000
        case .douyin1080p: return 5_000_000
        case .low:        return 8_000_000
        case .medium:     return 16_000_000
        case .high:       return 32_000_000
        case .original:   return nil
        }
    }
}

@MainActor
class VideoProcessor: ObservableObject {
    @Published var isHDR = false
    /// Whether to preserve HDR when exporting. Only shown when isHDR == true.
    /// When false, the export pipeline tone-maps to SDR (H.264).
    @Published var exportHDR = true
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
            self.exportHDR = detected   // default ON when HDR source
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
                        let pq  = kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String
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

    func extractCoverFrame(asset: AVAsset, at time: CMTime) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // Request HDR/wide-color output — keeps HLG/PQ color space in the returned CGImage.
        // Default is ForceSDR (tone-maps to 8-bit sRGB); MatchSource preserves HLG/PQ.
        // Available macOS 15+; on older versions we get a tone-mapped frame (graceful degradation).
        if #available(macOS 15.0, *) {
            generator.dynamicRangePolicy = .matchSource
        }
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
        bitratePreset: BitratePreset
    ) async throws -> URL {
        isProcessing = true
        progress = 0
        statusMessage = "Exporting video..."

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        let presetName = resolveExportPreset(bitratePreset: bitratePreset)

        try await exportWithExportSession(
            asset: asset,
            startTime: startTime,
            endTime: endTime,
            presetName: presetName,
            outputURL: outputURL
        )

        isProcessing = false
        progress = 1.0
        statusMessage = "Video export complete."
        return outputURL
    }

    /// Resolve AVAssetExportSession preset string from BitratePreset + HDR flag.
    ///
    /// Platform presets (.xhs720p / .douyin1080p):
    ///   Always H.264 (SDR) at a capped resolution — matching each platform's effective ceiling.
    ///   XHS re-encodes uploads to ≤720p/4 Mbps; Douyin tops out at 1080p/~5 Mbps.
    ///
    /// HDR path  → HEVC, preserving HLG/PQ transfer function + bt2020 primaries.
    /// SDR path  → H.264, tonemap HDR→SDR automatically.
    /// Original  → Passthrough (no re-encode).
    private func resolveExportPreset(bitratePreset: BitratePreset) -> String {
        switch bitratePreset {
        case .original:
            return AVAssetExportPresetPassthrough

        // ── Platform-specific ──────────────────────────────────────────────────
        case .xhs720p:
            // H.264 720p — XHS displays ≤720p for Live Photo MOV component; cap input here
            return AVAssetExportPreset1280x720

        case .douyin1080p:
            // H.264 1080p — Douyin's quality ceiling for video
            return AVAssetExportPreset1920x1080

        // ── Standard ──────────────────────────────────────────────────────────
        case .low:
            return isHDR && exportHDR
                ? AVAssetExportPresetHEVC1920x1080
                : AVAssetExportPresetMediumQuality

        case .medium:
            return isHDR && exportHDR
                ? AVAssetExportPresetHEVCHighestQuality
                : AVAssetExportPresetHighestQuality

        case .high:
            return isHDR && exportHDR
                ? AVAssetExportPresetHEVCHighestQuality
                : AVAssetExportPresetHighestQuality
        }
    }

    private func exportWithExportSession(
        asset: AVAsset,
        startTime: CMTime,
        endTime: CMTime,
        presetName: String,
        outputURL: URL
    ) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw LivePhotoError.exportSessionCreationFailed
        }

        session.outputURL = outputURL
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = false
        session.timeRange = CMTimeRange(start: startTime, end: endTime)

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
