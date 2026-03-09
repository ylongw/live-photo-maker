import SwiftUI
import AVFoundation
import AppKit

struct TimelineView: View {
    let duration: Double
    @Binding var coverTime: Double
    @Binding var startTime: Double
    @Binding var endTime: Double
    let thumbnails: [NSImage]
    /// Live preview of the cover frame — updated while dragging the red handle.
    var coverFramePreview: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(.headline)

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    // ── Thumbnail strip ──────────────────────────────────────────
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

                    if duration > 0 {
                        let startFrac  = startTime  / duration
                        let endFrac    = endTime    / duration
                        let coverFrac  = coverTime  / duration
                        let startX = startFrac  * Double(width)
                        let endX   = endFrac    * Double(width)
                        let coverX = coverFrac  * Double(width)

                        // ── Dim outside trim region ──────────────────────────────
                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: max(0, startX), height: 50)
                            .position(x: startX / 2, y: 25)

                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: max(0, Double(width) - endX), height: 50)
                            .position(x: endX + (Double(width) - endX) / 2, y: 25)

                        // ── Trim border ───────────────────────────────────────────
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: max(0, endX - startX), height: 50)
                            .position(x: startX + (endX - startX) / 2, y: 25)

                        // ── Cover frame indicator (red line + dot) ───────────────
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 2, height: 60)
                            .position(x: coverX, y: 25)

                        // ── Draggable cover frame handle ─────────────────────────
                        Circle()
                            .fill(Color.red)
                            .frame(width: 14, height: 14)
                            .shadow(radius: 1)
                            .position(x: coverX, y: -2)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let fraction = max(0, min(1, value.location.x / width))
                                        let newTime  = Double(fraction) * duration
                                        coverTime = max(startTime, min(endTime, newTime))
                                    }
                            )

                        // ── Cover frame preview popup ────────────────────────────
                        // Appears above the red handle while dragging or after update.
                        if let preview = coverFramePreview {
                            let previewW: Double = 96
                            let previewH: Double = 54
                            // Clamp so the preview doesn't overflow the timeline edges
                            let clampedX = min(max(previewW / 2, coverX), Double(width) - previewW / 2)

                            VStack(spacing: 2) {
                                Image(nsImage: preview)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: previewW, height: previewH)
                                    .cornerRadius(4)
                                    .clipped()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.red, lineWidth: 1.5)
                                    )
                                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)

                                // Small downward triangle indicator
                                Triangle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 5)
                            }
                            .position(x: clampedX, y: -(previewH / 2 + 12))
                            .animation(.easeInOut(duration: 0.1), value: coverX)
                        }
                    }
                }
            }
            .frame(height: 60)

            // ── Trim sliders ─────────────────────────────────────────────────────
            // NOTE: All range constraints are applied via .onChange to run DURING dragging,
            // not just on release. The cover slider uses a safe clamped range to prevent
            // a crash when lowerBound > upperBound (which happens if start > end mid-drag).
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Start: \(formatTime(startTime))")
                        .font(.caption).monospacedDigit()
                    Slider(value: $startTime, in: 0...max(duration, 0.01))
                        .onChange(of: startTime) { val in
                            // Prevent start overtaking end during drag
                            if val >= endTime { startTime = max(0, endTime - 0.1) }
                            if coverTime < startTime { coverTime = startTime }
                        }
                }
                VStack(alignment: .leading) {
                    Text("End: \(formatTime(endTime))")
                        .font(.caption).monospacedDigit()
                    Slider(value: $endTime, in: 0...max(duration, 0.01))
                        .onChange(of: endTime) { val in
                            // Prevent end overtaking start during drag
                            if val <= startTime { endTime = min(duration, startTime + 0.1) }
                            if coverTime > endTime { coverTime = endTime }
                        }
                }
                VStack(alignment: .leading) {
                    Text("Cover: \(formatTime(coverTime))")
                        .font(.caption).monospacedDigit()
                    // Safe range: always lower <= upper regardless of start/end order
                    let coverLower = min(startTime, endTime)
                    let coverUpper = max(startTime, endTime, 0.01)
                    Slider(value: $coverTime, in: coverLower...coverUpper)
                }
            }

            HStack {
                Text("Clip duration: \(formatTime(endTime - startTime))")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("Total: \(formatTime(duration))")
                    .font(.caption).foregroundColor(.secondary)
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

// Small downward-pointing triangle for the preview bubble pointer
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
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
                    thumbnails.append(NSImage(cgImage: cgImage,
                                             size: NSSize(width: cgImage.width, height: cgImage.height)))
                } catch { /* skip */ }
            }
        } catch {}

        return thumbnails
    }
}
