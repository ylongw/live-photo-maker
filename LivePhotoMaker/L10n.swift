import Foundation

// ── Language ──────────────────────────────────────────────────────────────────
enum AppLanguage: String, CaseIterable, Identifiable {
    case zh = "zh"
    case en = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

// ── L10n manager (ObservableObject so views auto-update) ──────────────────────
final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var lang: AppLanguage {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: "appLang") }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLang") ?? "zh"
        lang = AppLanguage(rawValue: saved) ?? .zh
    }

    /// Return the Chinese or English string based on current language.
    func t(_ zh: String, _ en: String) -> String {
        lang == .zh ? zh : en
    }

    // ── Cached string constants ───────────────────────────────────────────────
    var appName: String          { "LivePhotoMaker" }

    // Top bar
    var hdrBadge: String         { "HDR" }
    var changeVideo: String      { t("更换视频", "Change Video") }

    // File sidebar
    var filesHeader: String      { t("文件", "FILES") }
    var addVideos: String        { t("添加视频", "Add videos") }

    // Drop zone
    var dropTitle: String        { t("拖入视频", "Drop video here") }
    var dropSubtitle: String     { t("支持 MOV、MP4、M4V，HDR 直通", "MOV, MP4, M4V · HDR supported") }
    var selectFile: String       { t("选择文件", "Select File") }

    // Timeline
    var timeline: String         { t("时间轴", "Timeline") }
    var startLabel: String       { t("起点", "Start") }
    var endLabel: String         { t("终点", "End") }
    var coverLabel: String       { t("封帧", "Cover") }
    var clipDuration: String     { t("片段时长:", "Clip duration:") }
    var totalDuration: String    { t("总时长:", "Total:") }

    // Quick controls
    var loopPreview: String      { t("循环预览", "Loop Preview") }
    var seekToCover: String      { t("跳到封帧", "Seek to Cover") }
    var seekTooltip: String      { t("跳到封面帧所在位置", "Jump playhead to the selected cover frame position") }

    // Platform presets
    var optimizedFor: String     { t("优化导出:", "Optimized for:") }
    var myPresets: String        { t("我的预设:", "My Presets:") }
    var presetCustom: String     { t("自定义", "Custom") }

    // Save preset
    var presetNamePlaceholder: String { t("预设名称...", "Name...") }
    var save: String             { t("保存", "Save") }
    var savePresetTooltip: String { t("保存当前导出设置为预设", "Save current export settings as a named preset") }

    // Codec row
    var codecLabel: String       { t("编码", "Codec") }
    var codecH264Note: String    { t("兼容性好，文件较大", "Compatible · larger file") }
    var codecHevcNote: String    { t("文件较小，需 macOS 10.13+", "Smaller file · requires macOS 10.13+") }

    // Resolution row
    var resolutionLabel: String  { t("分辨率", "Resolution") }

    // Quality row
    var qualityLabel: String     { t("画质", "Quality") }

    // Frame rate row
    var frameRateLabel: String   { t("帧率", "Frame Rate") }
    var preservesFps: String     { t("※ 保持原始帧率", "※ preserves source fps") }

    // HDR row
    var hdrLabel: String         { t("HDR", "HDR") }
    var exportHDR: String        { t("导出 HDR", "Export HDR") }
    var hdrOnNote: String        { t("HEVC / H.265 — HLG 直通", "HEVC / H.265 — HLG preserved") }
    var hdrOffNote: String       { t("H.264 — tone-map 转 SDR", "H.264 — tone-mapped to SDR") }

    // Audio row
    var audioLabel: String       { t("音频", "Audio") }
    var muteLabel: String        { t("静音", "Mute") }
    var muteOnNote: String       { t("导出的 Live Photo 无声", "No audio in exported Live Photo") }
    var muteOffNote: String      { t("保留原始音频", "Keep original audio") }

    // XHS warning
    func xhsWarning(cur: Double, max: Double) -> String {
        t("片段 \(String(format: "%.1f", cur))s 超过 \(String(format: "%.1f", max))s，小红书 Live Photo 动效可能失效",
          "Clip \(String(format: "%.1f", cur))s exceeds \(String(format: "%.1f", max))s, XHS Live Photo effect may not play")
    }
    var autoCrop: String         { t("自动裁剪", "Auto Trim") }

    // Export bar
    var createLivePhoto: String  { t("创建 Live Photo", "Create Live Photo") }
    var saveToPhotos: String     { t("存入相册", "Save to Photos") }

    // Status messages (set on @MainActor, so L10n.shared access is fine)
    var statusExtractingCover: String   { t("提取封帧中...", "Extracting cover…") }
    var statusExportingClip: String     { t("导出视频片段...", "Exporting video clip…") }
    var statusExportCancelled: String   { t("已取消", "Export cancelled.") }
    var statusCreatingPair: String      { t("生成 Live Photo 配对...", "Creating Live Photo pair…") }
    var statusImporting: String         { t("导入相册...", "Importing to Photos…") }
    var statusSavedToPhotos: String     { t("Live Photo 已保存到相册！", "Live Photo saved to Photos!") }
    var statusExportingVideo: String    { t("导出视频...", "Exporting video...") }
    var statusExportComplete: String    { t("视频导出完成", "Video export complete.") }

    func statusSaved(img: String, vid: String) -> String {
        t("已保存！\(img) + \(vid)", "Saved! \(img) + \(vid)")
    }

    // Language toggle
    var langToggleLabel: String  { lang == .zh ? "EN" : "中" }
    var langToggleTooltip: String { lang == .zh ? "Switch to English" : "切换到中文" }

    func toggleLanguage() {
        lang = lang == .zh ? .en : .zh
    }
}
