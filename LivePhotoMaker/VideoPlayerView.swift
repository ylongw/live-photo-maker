import SwiftUI
import AVKit

struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = false
        enableEDR(playerView)
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        enableEDR(nsView)
    }

    /// Enable Extended Dynamic Range (HDR) rendering on the player view.
    /// This allows HLG / PQ content to display at full brightness on EDR-capable screens
    /// (Pro Display XDR, MacBook Pro XDR, etc.). On SDR screens this is a no-op.
    private func enableEDR(_ view: AVPlayerView) {
        view.wantsLayer = true
        if #available(macOS 14.0, *) {
            view.layer?.wantsExtendedDynamicRangeContent = true
            view.contentOverlayView?.wantsLayer = true
            view.contentOverlayView?.layer?.wantsExtendedDynamicRangeContent = true
        }
    }
}
