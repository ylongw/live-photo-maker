import Foundation
import Combine

// ── Data model ────────────────────────────────────────────────────────────────

struct SavedPreset: Codable, Identifiable, Equatable {
    var id:             UUID
    var name:           String
    var platformPreset: PlatformPreset
    var bitratePreset:  BitratePreset
    var exportHDR:      Bool

    init(
        id:             UUID           = UUID(),
        name:           String,
        platformPreset: PlatformPreset,
        bitratePreset:  BitratePreset,
        exportHDR:      Bool
    ) {
        self.id             = id
        self.name           = name
        self.platformPreset = platformPreset
        self.bitratePreset  = bitratePreset
        self.exportHDR      = exportHDR
    }

    /// One-line summary shown as a tooltip.
    var summary: String {
        var parts: [String] = []
        if platformPreset != .custom { parts.append(platformPreset.rawValue) }
        parts.append(bitratePreset.rawValue)
        if exportHDR { parts.append("HDR") }
        return parts.joined(separator: " · ")
    }
}

// ── Store (UserDefaults-backed) ────────────────────────────────────────────────

final class PresetStore: ObservableObject {
    @Published private(set) var presets: [SavedPreset] = []

    private let key = "com.livephotomaker.customPresets.v1"

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
