import SwiftUI
import AppKit

@main
struct LivePhotoMakerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(WindowTransparencyConfigurator())
        }
        .windowResizability(.contentMinSize)
    }
}

// Makes the window background transparent so NSVisualEffectView
// blends with the desktop — required for true Liquid Glass effect.
struct WindowTransparencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
