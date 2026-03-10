import SwiftUI
import AVFoundation
import AppKit

struct TimelineView: View {
    let duration: Double
    @Binding var coverTime: Double
    @Binding var startTime: Double
    @Binding var endTime: Double
    let thumbnails: [NSImage]
    var coverFramePreview: NSImage?

    // ── Drag state for trim handles ──────────────────────────────────────────
    // We record origin times at drag-start so translation math stays correct
    // even as the bindings update during the drag.
    @State private var startDragOrigin: Double? = nil
    @State private var endDragOrigin: Double? = nil
    @State private var panDragOriginStart: Double? = nil
    @State private var panDragOriginEnd: Double? = nil
    // Cover handle also needs origin — DragGesture.location is in the circle's
    // local frame (0…14 px), NOT the parent ZStack, so we must use translation.
    @State private var coverDragOrigin: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(.headline)

            GeometryReader { geometry in
                let W = geometry.size.width           // total width in points
                let startX = (startTime / max(duration, 0.001)) * Double(W)
                let endX   = (endTime   / max(duration, 0.001)) * Double(W)
                let coverX = (coverTime / max(duration, 0.001)) * Double(W)

                ZStack(alignment: .leading) {

                    // ── 1. Thumbnail strip ────────────────────────────────────
                    HStack(spacing: 0) {
                        ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, thumb in
                            Image(nsImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: W / max(CGFloat(thumbnails.count), 1), height: 50)
                                .clipped()
                        }
                    }
                    .frame(width: W, height: 50)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                    if duration > 0 {

                        // ── 2. Dim outside trim region ────────────────────────
                        Rectangle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: max(0, startX), height: 50)
                            .position(x: startX / 2, y: 25)

                        Rectangle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: max(0, Double(W) - endX), height: 50)
                            .position(x: endX + (Double(W) - endX) / 2, y: 25)

                        // ── 3. Yellow trim border (visual only) ───────────────
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: max(0, endX - startX), height: 50)
                            .position(x: startX + (endX - startX) / 2, y: 25)

                        // ── 4. Middle-pan gesture area ────────────────────────
                        // Drag the selected region to move start+end together.
                        // Placed BEFORE handles so handles have higher gesture priority.
                        let panW = max(0, endX - startX - 20)
                        if panW > 4 {
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .frame(width: panW, height: 50)
                                .position(x: startX + (endX - startX) / 2, y: 25)
                                .gesture(
                                    DragGesture(minimumDistance: 3)
                                        .onChanged { value in
                                            if panDragOriginStart == nil {
                                                panDragOriginStart = startTime
                                                panDragOriginEnd   = endTime
                                            }
                                            let dt = (Double(value.translation.width) / Double(W)) * duration
                                            let origStart = panDragOriginStart ?? startTime
                                            let origEnd   = panDragOriginEnd   ?? endTime
                                            let clipDur   = origEnd - origStart
                                            var ns = origStart + dt
                                            var ne = origEnd   + dt
                                            // clamp to [0, duration]
                                            if ns < 0 { ns = 0; ne = clipDur }
                                            if ne > duration { ne = duration; ns = duration - clipDur }
                                            startTime = ns
                                            endTime   = ne
                                            coverTime = max(ns, min(ne, coverTime))
                                        }
                                        .onEnded { _ in
                                            panDragOriginStart = nil
                                            panDragOriginEnd   = nil
                                        }
                                )
                        }

                        // ── 5. Cover frame line (visual) ──────────────────────
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 2, height: 60)
                            .position(x: coverX, y: 25)

                        // ── 6. Left trim handle ───────────────────────────────
                        trimHandle(color: .yellow, x: startX)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if startDragOrigin == nil { startDragOrigin = startTime }
                                        let originX = ((startDragOrigin ?? startTime) / max(duration, 0.001)) * Double(W)
                                        let newX    = max(0, min(endX - 8, originX + Double(value.translation.width)))
                                        startTime   = (newX / Double(W)) * duration
                                        if coverTime < startTime { coverTime = startTime }
                                    }
                                    .onEnded { _ in startDragOrigin = nil }
                            )

                        // ── 7. Right trim handle ──────────────────────────────
                        trimHandle(color: .yellow, x: endX)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if endDragOrigin == nil { endDragOrigin = endTime }
                                        let originX = ((endDragOrigin ?? endTime) / max(duration, 0.001)) * Double(W)
                                        let newX    = max(startX + 8, min(Double(W), originX + Double(value.translation.width)))
                                        endTime     = (newX / Double(W)) * duration
                                        if coverTime > endTime { coverTime = endTime }
                                    }
                                    .onEnded { _ in endDragOrigin = nil }
                            )

                        // ── 8. Cover frame drag handle (highest priority) ─────
                        // Use translation+origin (same pattern as trim handles).
                        // value.location.x is in the circle's local 14×14 frame,
                        // NOT the parent ZStack — using it directly gave wrong math.
                        Circle()
                            .fill(Color.red)
                            .frame(width: 14, height: 14)
                            .shadow(radius: 1)
                            .position(x: coverX, y: -2)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if coverDragOrigin == nil { coverDragOrigin = coverTime }
                                        let originX = ((coverDragOrigin ?? coverTime) / max(duration, 0.001)) * Double(W)
                                        let newX    = max(0, min(Double(W), originX + Double(value.translation.width)))
                                        coverTime   = max(startTime, min(endTime, (newX / Double(W)) * duration))
                                    }
                                    .onEnded { _ in coverDragOrigin = nil }
                            )

                        // ── 9. Cover frame preview popup ──────────────────────
                        if let preview = coverFramePreview {
                            let pw: Double = 96, ph: Double = 54
                            let clampedX = min(max(pw / 2, coverX), Double(W) - pw / 2)
                            VStack(spacing: 2) {
                                Image(nsImage: preview)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: pw, height: ph)
                                    .cornerRadius(4)
                                    .clipped()
                                    .overlay(RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.red, lineWidth: 1.5))
                                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                                Triangle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 5)
                            }
                            .position(x: clampedX, y: -(ph / 2 + 12))
                            .animation(.easeInOut(duration: 0.1), value: coverX)
                        }
                    }
                }
            }
            .frame(height: 60)

            // ── Precision sliders (fine-tuning) ──────────────────────────────
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Start: \(formatTime(startTime))")
                        .font(.caption).monospacedDigit()
                    Slider(value: $startTime, in: 0...max(duration, 0.01))
                        .onChange(of: startTime) { val in
                            if val >= endTime { startTime = max(0, endTime - 0.1) }
                            if coverTime < startTime { coverTime = startTime }
                        }
                }
                VStack(alignment: .leading) {
                    Text("End: \(formatTime(endTime))")
                        .font(.caption).monospacedDigit()
                    Slider(value: $endTime, in: 0...max(duration, 0.01))
                        .onChange(of: endTime) { val in
                            if val <= startTime { endTime = min(duration, startTime + 0.1) }
                            if coverTime > endTime { coverTime = endTime }
                        }
                }
                VStack(alignment: .leading) {
                    Text("Cover: \(formatTime(coverTime))")
                        .font(.caption).monospacedDigit()
                    let lo = min(startTime, endTime)
                    let hi = max(startTime, endTime, 0.01)
                    Slider(value: $coverTime, in: lo...hi)
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

    // ── Reusable trim handle view ─────────────────────────────────────────────
    // A narrow visual bar + wider transparent hit area, positioned at `x`.
    @ViewBuilder
    private func trimHandle(color: Color, x: Double) -> some View {
        ZStack {
            // Visual bar
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 5, height: 52)
                .shadow(color: .black.opacity(0.3), radius: 1)
            // Wide transparent hit area for easier dragging
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: 22, height: 52)
        }
        .position(x: x, y: 25)
        .cursor(.resizeLeftRight)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", mins, secs, frac)
    }
}

// Resize cursor on hover
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

// Downward triangle for preview bubble
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

class ThumbnailGenerator {
    static func generateThumbnails(asset: AVAsset, count: Int = 10) async -> [NSImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)

        var thumbnails: [NSImage] = []
        do {
            let duration = try await asset.load(.duration)
            let total = CMTimeGetSeconds(duration)
            guard total > 0 else { return [] }
            for i in 0..<count {
                let t = CMTime(seconds: total * Double(i) / Double(count), preferredTimescale: 600)
                if let (cg, _) = try? await generator.image(at: t) {
                    thumbnails.append(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
                }
            }
        } catch {}
        return thumbnails
    }
}
