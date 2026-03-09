import AVFoundation
import CoreImage
import CoreVideo
import AppKit
import UniformTypeIdentifiers

enum BitratePreset: String, CaseIterable, Identifiable {
    case low = "Low (8 Mbps)"
    case medium = "Medium (16 Mbps)"
    case high = "High (32 Mbps)"
    case original = "Original"

    var id: String { rawValue }

    var bitsPerSecond: Int? {
        switch self {
        case .low: return 8_000_000
        case .medium: return 16_000_000
        case .high: return 32_000_000
        case .original: return nil
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

    /// Choose the right AVAssetExportSession preset based on bitrate + HDR flag.
    ///
    /// HDR path  → HEVC (H.265), which natively carries HLG/PQ metadata.
    ///             AVAssetExportPresetHEVCHighestQuality preserves the transfer function
    ///             and color primaries from the source.
    /// SDR path  → H.264 presets, which tonemap HDR → SDR automatically.
    /// Original  → Passthrough (no re-encode); always preserves HDR if present.
    private func resolveExportPreset(bitratePreset: BitratePreset) -> String {
        switch bitratePreset {
        case .original:
            return AVAssetExportPresetPassthrough

        case .low:
            return isHDR && exportHDR
                ? AVAssetExportPresetHEVC1920x1080         // HEVC 1080p — smaller, still HDR
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
