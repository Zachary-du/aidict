import Foundation
import Combine
import SwiftUI

public final class SettingsStore: ObservableObject, @unchecked Sendable {
    public static let shared = SettingsStore()

    private let ud = UserDefaults.standard

    // MARK: - 取词开关
    @AppStorage("is_hover_lookup_enabled")   public var isHoverLookupEnabled: Bool = true    { willSet { objectWillChange.send() } }
    @AppStorage("is_shortcut_lookup_enabled") public var isShortcutLookupEnabled: Bool = true { willSet { objectWillChange.send() } }
    @AppStorage("hover_delay")               public var hoverDelay: Double = 0.45            { willSet { objectWillChange.send() } }
    @AppStorage("hover_requires_option_key") public var hoverRequiresOptionKey: Bool = false  { willSet { objectWillChange.send() } }
    @AppStorage("play_audio_on_lookup")      public var playAudioOnLookup: Bool = false       { willSet { objectWillChange.send() } }
    /// 发音口音偏好: "us" = 美式英语, "uk" = 英式英语
    @AppStorage("preferred_accent")          public var preferredAccent: String = "us"        { willSet { objectWillChange.send() } }

    /// 悬停取词时是否自动触发 AI 联网查询（默认关闭以节省宝贵配额；关闭时 HUD 显示一键深度解析按钮）
    @AppStorage("ai_auto_trigger_on_hover")  public var aiAutoTriggerOnHover: Bool = false    { willSet { objectWillChange.send() } }
    /// 是否在悬浮窗旁延迟展示概念图解与直观理解伴侣卡
    @AppStorage("show_intuitive_companion")  public var showIntuitiveCompanion: Bool = true   { willSet { objectWillChange.send() } }

    // MARK: - 发音与 AI 神经语音 (Neural TTS)
    /// 语音引擎偏好: "neural" = AI 神经拟真发音 (超自然免配置), "openai" = OpenAI TTS, "system" = macOS系统语音
    @AppStorage("tts_engine")                public var ttsEngine: String = "neural"          { willSet { objectWillChange.send() } }
    /// OpenAI TTS 音色: alloy, echo, fable, onyx, nova, shimmer
    @AppStorage("openai_tts_voice")          public var openaiTTSVoice: String = "alloy"      { willSet { objectWillChange.send() } }
    /// OpenAI TTS 独立端点（留空则默认 https://api.openai.com/v1/audio/speech）
    @AppStorage("openai_tts_endpoint")       public var openaiTTSEndpoint: String = ""        { willSet { objectWillChange.send() } }

    // MARK: - HUD 窗口自定义尺寸
    @AppStorage("hud_width")                 public var hudWidth: Double = 460                { willSet { objectWillChange.send() } }
    @AppStorage("hud_height")                public var hudHeight: Double = 520               { willSet { objectWillChange.send() } }

    // MARK: - AI 配置（用 UserDefaults 直读直写，不用 @AppStorage 默认值机制覆盖已存值）
    public var aiEndpoint: String {
        get { ud.string(forKey: "ai_endpoint") ?? "" }
        set { ud.set(newValue, forKey: "ai_endpoint"); objectWillChange.send() }
    }
    public var aiApiKey: String {
        get { ud.string(forKey: "ai_api_key") ?? "" }
        set { ud.set(newValue, forKey: "ai_api_key"); objectWillChange.send() }
    }
    public var aiModel: String {
        get { ud.string(forKey: "ai_model") ?? "" }
        set { ud.set(newValue, forKey: "ai_model"); objectWillChange.send() }
    }
    /// 自定义 AI 系统提示词（留空使用默认）
    public var aiSystemPrompt: String {
        get { ud.string(forKey: "ai_system_prompt") ?? "" }
        set { ud.set(newValue, forKey: "ai_system_prompt"); objectWillChange.send() }
    }
    /// 自定义用户提示词模板，支持 {word} 和 {context} 占位符（留空使用默认）
    public var aiUserPromptTemplate: String {
        get { ud.string(forKey: "ai_user_prompt_template") ?? "" }
        set { ud.set(newValue, forKey: "ai_user_prompt_template"); objectWillChange.send() }
    }
    public var merriamWebsterAPIKey: String {
        get { ud.string(forKey: "mw_api_key") ?? "" }
        set { ud.set(newValue, forKey: "mw_api_key"); objectWillChange.send() }
    }
    /// Pixabay API Key（可选，用于检索生动矢量插画；留空时自动降级使用 Wikipedia 免 Key 官方图库）
    public var pixabayApiKey: String {
        get { ud.string(forKey: "pixabay_api_key") ?? "" }
        set { ud.set(newValue, forKey: "pixabay_api_key"); objectWillChange.send() }
    }

    // MARK: - 启用的词典源
    @Published public var enabledSources: Set<String> {
        didSet { ud.set(Array(enabledSources), forKey: "enabled_sources") }
    }

    // MARK: - 词典源显示顺序（ID 数组，决定查词和展示的先后顺序）
    /// 用户自定义的词典源顺序，按此顺序展示并查询
    @Published public var sourceOrder: [String] {
        didSet { ud.set(sourceOrder, forKey: "source_order"); objectWillChange.send() }
    }

    private init() {
        var sources = Set(ud.stringArray(forKey: "enabled_sources") ?? ["longman", "collins_cobuild", "system_oxford", "free_dictionary_api", "wiktionary", "ai_engine"])
        sources.insert("longman")
        sources.insert("collins_cobuild")
        self.enabledSources = sources

        if let order = ud.stringArray(forKey: "source_order"), !order.isEmpty {
            var updatedOrder = order
            // 确保长效默认前置 longman 和 collins_cobuild
            if !updatedOrder.contains("longman") {
                updatedOrder.insert("longman", at: 0)
            }
            if !updatedOrder.contains("collins_cobuild") {
                let insertIdx = updatedOrder.firstIndex(of: "longman").map { $0 + 1 } ?? 0
                updatedOrder.insert("collins_cobuild", at: min(insertIdx, updatedOrder.count))
            }
            self.sourceOrder = updatedOrder
        } else {
            // 默认顺序（朗文与柯林斯高阶置顶）
            self.sourceOrder = ["longman", "collins_cobuild", "system_oxford", "free_dictionary_api", "wiktionary",
                                "merriam_webster", "ai_engine", "custom_dict"]
        }
        // 自动将错误/受限模型迁移至高配额稳定的 gemini-2.0-flash
        let curModel = ud.string(forKey: "ai_model") ?? ""
        if curModel.isEmpty || curModel == "gemini-3.6-flash" || curModel == "gemini-2.5-flash" {
            ud.set("gemini-2.0-flash", forKey: "ai_model")
        }

        // 若用户本地缓存了带有"心智模型"或"核心画面"的长篇认知提示词，平滑清空以应用简洁清晰的翻译版本
        let curSysPrompt = ud.string(forKey: "ai_system_prompt") ?? ""
        if curSysPrompt.contains("心智模型") || curSysPrompt.contains("认知语言学") || curSysPrompt.contains("核心画面") {
            ud.removeObject(forKey: "ai_system_prompt")
        }
        let curTemplate = ud.string(forKey: "ai_user_prompt_template") ?? ""
        if curTemplate.contains("心智模型") || curTemplate.contains("核心画面") {
            ud.removeObject(forKey: "ai_user_prompt_template")
        }
        aLog("SettingsStore 初始化 — ai_endpoint='\(ud.string(forKey: "ai_endpoint") ?? "(nil)")'  ai_model='\(ud.string(forKey: "ai_model") ?? "(nil)")'")
    }

    public func isSourceEnabled(_ id: String) -> Bool { enabledSources.contains(id) }

    public func toggleSource(_ id: String) {
        if enabledSources.contains(id) { enabledSources.remove(id) }
        else { enabledSources.insert(id) }
        objectWillChange.send()
    }

    /// 确保 sourceOrder 包含所有已知 source ID（新加入核心词典优先前置）
    public func syncSourceOrder(allSourceIds: [String]) {
        var order = sourceOrder
        for id in allSourceIds where !order.contains(id) {
            if id == "longman" {
                order.insert(id, at: 0)
            } else if id == "collins_cobuild" {
                let idx = order.firstIndex(of: "longman").map { $0 + 1 } ?? 0
                order.insert(id, at: min(idx, order.count))
            } else {
                order.append(id)
            }
        }
        // 移除已不存在的 ID（已删除的自定义词典等）
        order = order.filter { allSourceIds.contains($0) }
        if order != sourceOrder { sourceOrder = order }
    }
}
