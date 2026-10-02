import Foundation
import Combine
import SwiftUI

public final class DictionaryEngine: ObservableObject, @unchecked Sendable {
    public static let shared = DictionaryEngine()

    @Published public var currentWord: String = ""
    @Published public var correctedFromWord: String? = nil
    @Published public var contextSentence: String? = nil
    @Published public var sourceAppName: String? = nil
    @Published public var results: [DictionaryResult] = []
    @Published public var isSearching: Bool = false

    // 内置固定词典源（不随自定义词典变化，朗文与柯林斯优先前置）
    private let builtinSources: [any DictionarySource] = [
        LongmanDictionarySource(),
        CollinsDictionarySource(),
        SystemDictionarySource(),
        FreeDictionarySource(),
        WiktionarySource(),
        MerriamWebsterSource(),
        AIDictionarySource()
    ]

    // 当前自定义词典源（每本独立，动态更新）
    @Published private var customSources: [SingleCustomDictionarySource] = []

    private var activeTask: Task<Void, Never>?
    private var notificationObserver: Any?

    /// 所有词典源 = 内置 + 动态自定义
    public var allSources: [any DictionarySource] {
        builtinSources + customSources
    }

    private init() {
        refreshCustomSources()
        syncOrder()

        // 监听词典导入/删除通知，自动刷新
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .customDictionariesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshCustomSources()
            self?.syncOrder()
        }
    }

    deinit {
        if let obs = notificationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    /// 从数据库读取所有自定义词典，构建独立源列表
    public func refreshCustomSources() {
        let metas = CustomDictionaryStore.shared.allDictionaries()
        customSources = metas.map { SingleCustomDictionarySource(meta: $0) }
        aLog("DictionaryEngine: 已加载 \(customSources.count) 本自定义词典")
    }

    /// 确保 sourceOrder 包含所有当前源
    private func syncOrder() {
        let ids = allSources.map { $0.id }
        SettingsStore.shared.syncSourceOrder(allSourceIds: ids)
    }

    /// 按用户自定义顺序排列并过滤启用的词典源
    public var orderedEnabledSources: [any DictionarySource] {
        let order = SettingsStore.shared.sourceOrder
        let enabled = SettingsStore.shared.enabledSources
        let ordered = allSources.sorted { a, b in
            let ai = order.firstIndex(of: a.id) ?? Int.max
            let bi = order.firstIndex(of: b.id) ?? Int.max
            return ai < bi
        }
        return ordered.filter { enabled.contains($0.id) }
    }

    /// 是否为整句
    public var isSentence: Bool {
        let trimmed = currentWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        return wordCount >= 6 || trimmed.contains(". ") || trimmed.contains("? ") || trimmed.contains("! ") ||
               trimmed.hasSuffix(".") || trimmed.hasSuffix("?") || trimmed.hasSuffix("!") ||
               trimmed.hasSuffix("。") || trimmed.hasSuffix("？") || trimmed.hasSuffix("！")
    }

    /// 是否为短语
    public var isPhrase: Bool {
        let trimmed = currentWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        return wordCount >= 2 && !isSentence
    }

    public func lookup(
        word: String,
        context: String? = nil,
        sourceApp: String? = nil,
        triggerSource: TriggerSource = .manual
    ) {
        let sanitized = OCRNormalizer.shared.normalizeQueryText(word)
        guard !sanitized.isEmpty else { return }

        let queryWord = sanitized

        activeTask?.cancel()

        self.currentWord = queryWord
        self.correctedFromWord = nil
        self.contextSentence = context
        self.sourceAppName = sourceApp
        self.isSearching = true

        // 若开启了伴侣卡且为单单词，通知 HUDCompanionPanel 异步延迟呈现示意图与直观理解
        let isSingleWord = !queryWord.contains(" ") && queryWord.count <= 35
        let showCompanion = SettingsStore.shared.showIntuitiveCompanion && isSingleWord
        Task { @MainActor in
            if showCompanion {
                HUDCompanionPanel.shared.prepareAndShowDelayed(for: queryWord, parentPanel: HUDPanel.shared)
            } else {
                HUDCompanionPanel.shared.dismiss()
            }
        }

        let enabledSources = orderedEnabledSources
        let isMultiWord = queryWord.contains(" ")
        let autoRunAI = (triggerSource == .manual) || SettingsStore.shared.aiAutoTriggerOnHover || isMultiWord

        // 初始化各数据源的加载骨架（悬停且未开启自动AI时，AI 源直接呈现为待触发 .idle 状态）
        self.results = enabledSources.map { source in
            if source.id == "ai_engine" && !autoRunAI {
                return DictionaryResult(
                    sourceId: source.id,
                    sourceName: source.name,
                    word: queryWord,
                    status: .idle
                )
            }
            return DictionaryResult(
                sourceId: source.id,
                sourceName: source.name,
                word: queryWord,
                status: .loading
            )
        }

        activeTask = Task { @MainActor in
            await withTaskGroup(of: DictionaryResult.self) { group in
                for source in enabledSources {
                    if source.id == "ai_engine" && !autoRunAI {
                        // 跳过自动触发，等待用户主动点击卡片上的深度解析按钮，保护每日配额
                        continue
                    }
                    group.addTask {
                        do {
                            return try await source.lookup(word: queryWord, context: context)
                        } catch {
                            return DictionaryResult(
                                sourceId: source.id,
                                sourceName: source.name,
                                word: queryWord,
                                status: .failure(error.localizedDescription)
                            )
                        }
                    }
                }

                for await result in group {
                    if Task.isCancelled { break }
                    if let index = self.results.firstIndex(where: { $0.sourceId == result.sourceId }) {
                        self.results[index] = result
                    }
                    if result.sourceId == "ai_engine",
                       let aiText = result.aiAnalysis ?? result.definitions.first?.meaning,
                       !aiText.isEmpty {
                        VocabularyStore.shared.updateDefinitionIfSaved(
                            word: queryWord,
                            definition: aiText,
                            imageUrl: WordImageService.shared.currentImageURL
                        )
                    }
                }
            }

            self.isSearching = false

            // 记录查词历史
            let ph = self.results.compactMap({ $0.phonetic ?? $0.phonetic_uk }).first
            let summary = self.results.compactMap({ $0.definitions.first?.meaning }).first ?? ""
            HistoryStore.shared.recordLookup(word: queryWord, phonetic: ph, summary: summary)

            // 若配置了自动发音，查询完成后播放首个可用音频或 TTS
            if SettingsStore.shared.playAudioOnLookup {
                let accent = SettingsStore.shared.preferredAccent
                let usAudio = self.results.compactMap({ $0.audioURL }).first
                let ukAudio = self.results.compactMap({ $0.audioURL_uk }).first
                AudioPlayer.shared.speak(text: queryWord, audioURL: usAudio, audioURL_uk: ukAudio, accent: accent)
            }
        }
    }

    /// 用户在 HUD 卡片上手动点击触发 AI 语境深度解析
    public func triggerAIAnalysis() {
        guard !currentWord.isEmpty else { return }
        guard let aiSource = allSources.first(where: { $0.id == "ai_engine" }) else { return }
        
        let word = self.currentWord
        let context = self.contextSentence

        if let index = self.results.firstIndex(where: { $0.sourceId == "ai_engine" }) {
            self.results[index].status = .loading
        }

        Task { @MainActor in
            do {
                let res = try await aiSource.lookup(word: word, context: context)
                if let index = self.results.firstIndex(where: { $0.sourceId == "ai_engine" }) {
                    self.results[index] = res
                }
            } catch {
                if let index = self.results.firstIndex(where: { $0.sourceId == "ai_engine" }) {
                    self.results[index] = DictionaryResult(
                        sourceId: "ai_engine",
                        sourceName: "AI 语境分析",
                        word: word,
                        status: .failure(error.localizedDescription)
                    )
                }
            }
        }
    }
}
