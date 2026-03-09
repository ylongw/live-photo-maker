import SwiftUI
import AVFoundation
import AppKit

struct TimelineView: View {
    let duration: Double
    @Binding var coverTime: Double
    @Binding var startTime: Double
    @Binding var endTime: Double
    let thumbnails: [NSImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thumbnail strip with overlay handles
            Text("Timeline")
                .font(.headline)

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    // Thumbnail strip
                    HStack(spacing: 0) {
                        ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, thumb in
                            Image(nsImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(
                                    width: width / max(CGFloat(thumbnails.count), 1),
                                    height: 50
                                )
                                .clipped()
                        }
                    }
                    .frame(width: width, height: 50)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                    // Trim region overlay
                    if duration > 0 {
                        let startFraction = startTime / duration
                        let endFraction = endTime / duration
                        let startX = startFraction * Double(width)
                        let endX = endFraction * Double(width)

                        // Dimmed regions outside trim
                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: max(0, startX), height: 50)
                            .position(x: startX / 2, y: 25)

                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: max(0, Double(width) - endX), height: 50)
                            .position(x: endX + (Double(width) - endX) / 2, y: 25)

                        // Trim border
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: max(0, endX - startX), height: 50)
                            .position(x: startX + (endX - startX) / 2, y: 25)

                        // Cover frame indicator (red line)
                        let coverFraction = coverTime / duration
                        let coverX = coverFraction * Double(width)
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 2, height: 60)
                            .position(x: coverX, y: 25)

                        // Draggable cover frame handle
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .position(x: coverX, y: -2)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let fraction = max(0, min(1, value.location.x / width))
                                        let newTime = Double(fraction) * duration
                                        coverTime = max(startTime, min(endTime, newTime))
                                    }
                            )
                    }
                }
            }
            .frame(height: 60)

            // Trim controls
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Start: \(formatTime(startTime))")
                        .font(.caption)
                        .monospacedDigit()
                    Slider(value: $startTime, in: 0...max(duration, 0.01)) { _ in
                        if startTime >= endTime {
                            startTime = max(0, endTime - 0.1)
                        }
                        if coverTime < startTime {
                            coverTime = startTime
                        }
                    }
                }

                VStack(alignment: .leading) {
                    Text("End: \(formatTime(endTime))")
                        .font(.caption)
                        .monospacedDigit()
                    Slider(value: $endTime, in: 0...max(duration, 0.01)) { _ in
                        if endTime <= startTime {
                            endTime = min(duration, startTime + 0.1)
                        }
                        if coverTime > endTime {
                            coverTime = endTime
                        }
                    }
                }

                VStack(alignment: .leading) {
                    Text("Cover: \(formatTime(coverTime))")
                        .font(.caption)
                        .monospacedDigit()
                    Slider(value: $coverTime, in: max(0, startTime)...max(endTime, 0.01))
                }
            }

            // Duration info
            HStack {
                Text("Clip duration: \(formatTime(endTime - startTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Total: \(formatTime(duration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", mins, secs, frac)
    }
}

// Thumbnail generator
class ThumbnailGenerator {
    static func generateThumbnails(asset: AVAsset, count: Int = 10) async -> [NSImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)

        var thumbnails: [NSImage] = []

        do {
            let duration = try await asset.load(.duration)
            let totalSeconds = CMTimeGetSeconds(duration)
            guard totalSeconds > 0 else { return [] }

            for i in 0..<count {
                let time = CMTime(
                    seconds: totalSeconds * Double(i) / Double(count),
                    preferredTimescale: 600
                )
                do {
                    let (cgImage, _) = try await generator.image(at: time)
                    let nsImage = NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    )
                    thumbnails.append(nsImage)
                } catch {
                    // Skip failed thumbnails
                }
            }
        } catch {
            // Return whatever we have
        }

        return thumbnails
    }
}
