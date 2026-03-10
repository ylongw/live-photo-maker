import Foundation
import Combine

// ── Data model ────────────────────────────────────────────────────────────────

struct SavedPreset: Codable, Identifiable, Equatable {
    var id:       UUID
    var name:     String
    var settings: ExportSettings
    var platform: PlatformPreset   // context for display / suggested platform

    init(id: UUID = UUID(), name: String, settings: ExportSettings, platform: PlatformPreset) {
        self.id       = id
        self.name     = name
        self.settings = settings
        self.platform = platform
    }

    /// One-line summary shown as tooltip or subtitle.
    var summary: String {
        var parts: [String] = []
        if platform != .custom { parts.append(platform.rawValue) }
        parts.append(settings.codec.rawValue)
        parts.append(settings.resolution.rawValue)
        parts.append(settings.quality.rawValue)
        if settings.exportHDR { parts.append("HDR") }
        return parts.joined(separator: " · ")
    }
}

// ── Store (UserDefaults-backed) ────────────────────────────────────────────────

final class PresetStore: ObservableObject {
    @Published private(set) var presets: [SavedPreset] = []

    private let key = "com.livephotomaker.customPresets.v2"

    init() { load() }

    func add(_ preset: SavedPreset) {
        presets.append(preset)
        persist()
    }

    func delete(_ preset: SavedPreset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    func rename(_ preset: SavedPreset, to newName: String) {
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx].name = newName
            persist()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedPreset].self, from: data)
        else { return }
        presets = decoded
    }
}
