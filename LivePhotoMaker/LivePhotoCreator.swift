import AVFoundation
import CoreGraphics
import Photos
import UniformTypeIdentifiers

class LivePhotoCreator {

    /// Creates a Live Photo pair by stamping both the image and video with the same content identifier UUID.
    /// Returns the directory containing the paired files.
    func createLivePhoto(
        coverImage: CGImage,
        videoURL: URL,
        outputDirectory: URL
    ) async throws -> (imageURL: URL, videoURL: URL) {
        let uuid = UUID().uuidString

        // Write the cover image as HEIC with the content identifier
        let imageURL = outputDirectory.appendingPathComponent("IMG_\(uuid).heic")
        try writeImageWithContentIdentifier(cgImage: coverImage, uuid: uuid, to: imageURL)

        // Write the video with the content identifier
        let pairedVideoURL = outputDirectory.appendingPathComponent("IMG_\(uuid).mov")
        try await writeVideoWithContentIdentifier(sourceURL: videoURL, uuid: uuid, to: pairedVideoURL)

        return (imageURL: imageURL, videoURL: pairedVideoURL)
    }

    /// Writes a CGImage as HEIC with the Apple Content Identifier in MakerApple dictionary (key 17).
    private func writeImageWithContentIdentifier(cgImage: CGImage, uuid: String, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            throw LivePhotoError.failedToCreateImageDestination
        }

        // The content identifier goes into the MakerApple dictionary at key 17.
        // This is what Apple uses to pair a still image with its Live Photo video.
        let makerAppleDict: [String: Any] = [
            "17": uuid
        ]

        let properties: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: makerAppleDict
        ]

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        if !CGImageDestinationFinalize(destination) {
            throw LivePhotoError.failedToWriteImage
        }
    }

    /// Writes the video MOV file with the content identifier metadata using AVAssetExportSession.
    private func writeVideoWithContentIdentifier(sourceURL: URL, uuid: String, to outputURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw LivePhotoError.failedToWriteMetadata
        }

        // Add content identifier metadata
        let idItem = AVMutableMetadataItem()
        idItem.keySpace = .quickTimeMetadata
        idItem.key = "com.apple.quicktime.content.identifier" as NSString
        idItem.value = uuid as NSString
        idItem.dataType = "com.apple.metadata.datatype.UTF-8"

        // Add still-image-time metadata (required for Live Photos)
        let timeItem = AVMutableMetadataItem()
        timeItem.keySpace = .quickTimeMetadata
        timeItem.key = "com.apple.quicktime.still-image-time" as NSString
        timeItem.value = NSNumber(value: -1)
        timeItem.dataType = "com.apple.metadata.datatype.int8"

        session.metadata = [idItem, timeItem]
        session.outputURL = outputURL
        session.outputFileType = .mov

        await session.export()

        if let error = session.error {
            throw error
        }

        guard session.status == .completed else {
            throw LivePhotoError.contentIdentifierWriteFailed
        }
    }

    /// Import the Live Photo pair into Photos.app using PHPhotoLibrary.
    func importToPhotos(imageURL: URL, videoURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized else {
            throw LivePhotoError.failedToWriteMetadata
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false

            request.addResource(with: .photo, fileURL: imageURL, options: options)
            request.addResource(with: .pairedVideo, fileURL: videoURL, options: options)
        }
    }
}
