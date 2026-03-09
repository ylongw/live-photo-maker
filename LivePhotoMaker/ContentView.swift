import SwiftUI
import AVKit
import AVFoundation
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var processor = VideoProcessor()
    @State private var player: AVPlayer?
    @State private var asset: AVAsset?
    @State private var videoURL: URL?

    @State private var coverTime: Double = 0
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var bitratePreset: BitratePreset = .medium
    @State private var thumbnails: [NSImage] = []

    @State private var isDragOver = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("LivePhotoMaker")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                if processor.isHDR {
                    Label("HDR", systemImage: "sparkles.tv")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.purple.opacity(0.2))
                        )
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
                            thumbnails: thumbnails
                        )
                        .padding(.horizontal)

                        // Controls
                        VStack(spacing: 12) {
                            // Bitrate selector
                            HStack {
                                Text("Bitrate:")
                                    .font(.subheadline)
                                Picker("", selection: $bitratePreset) {
                                    ForEach(BitratePreset.allCases) { preset in
                                        Text(preset.rawValue).tag(preset)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 500)
                            }

                            // Seek button
                            HStack {
                                Button("Seek to Cover Frame") {
                                    let time = CMTime(seconds: coverTime, preferredTimescale: 600)
                                    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                                }
                                .controlSize(.small)

                                Spacer()

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
        .frame(minWidth: 700, minHeight: 550)
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
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
            UTType.movie,
            UTType.mpeg4Movie,
            UTType.quickTimeMovie,
            UTType(filenameExtension: "m4v") ?? .movie,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            loadVideo(url: url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            let supportedExtensions = ["mov", "mp4", "m4v", "avi", "mkv"]
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                Task { @MainActor in
                    errorMessage = "Unsupported file format. Please use MOV, MP4, or M4V."
                    showError = true
                }
                return
            }

            Task { @MainActor in
                loadVideo(url: url)
            }
        }
        return true
    }

    private func loadVideo(url: URL) {
        videoURL = url
        let avAsset = AVAsset(url: url)
        asset = avAsset
        player = AVPlayer(url: url)
        player?.pause()

        Task {
            _ = await processor.loadAsset(url: url)

            // Set default trim: full video or max 3 seconds
            let totalDuration = processor.duration
            startTime = 0
            endTime = min(totalDuration, 3.0)
            coverTime = 0

            // Generate thumbnails
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
                    bitratePreset: bitratePreset
                )

                processor.statusMessage = "Creating Live Photo pair..."
                processor.progress = 0.9

                // Let the user choose where to save
                let savePanel = NSSavePanel()
                savePanel.title = "Save Live Photo"
                savePanel.message = "Choose a folder to save the Live Photo files"
                savePanel.nameFieldStringValue = "LivePhoto"
                savePanel.canCreateDirectories = true
                // Save as a folder
                savePanel.allowedContentTypes = [.folder]

                // Actually use a directory picker instead
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

                // Clean up temp video
                try? FileManager.default.removeItem(at: exportedVideoURL)

                processor.isProcessing = false
                processor.progress = 1.0
                processor.statusMessage = "Live Photo saved! Image: \(result.imageURL.lastPathComponent), Video: \(result.videoURL.lastPathComponent)"

                // Reveal in Finder
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
                    bitratePreset: bitratePreset
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

                // Clean up temp files
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
