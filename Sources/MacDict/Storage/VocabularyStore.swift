import Foundation
import Combine
import SwiftUI

public struct VocabularyItem: Identifiable, Codable, Sendable {
    public var id: UUID
    public var word: String
    public var phonetic: String?
    public var definition: String
    public var contextSentence: String?
    public var sourceAppName: String?
    public var dateAdded: Date
    public var isStarred: Bool
    public var imageUrl: String?

    public init(
        id: UUID = UUID(),
        word: String,
        phonetic: String? = nil,
        definition: String,
        contextSentence: String? = nil,
        sourceAppName: String? = nil,
        dateAdded: Date = Date(),
        isStarred: Bool = true,
        imageUrl: String? = nil
    ) {
        self.id = id
        self.word = word
        self.phonetic = phonetic
        self.definition = definition
        self.contextSentence = contextSentence
        self.sourceAppName = sourceAppName
        self.dateAdded = dateAdded
        self.isStarred = isStarred
        self.imageUrl = imageUrl
    }

    /// 判断当前释义是否为大模型生成的结构化深度解析（包含心智模型与认知意象）
    public var isAIDefinition: Bool {
        let def = definition
        return def.contains("核心画面") || def.contains("灵魂本义") || def.contains("具象通俗场景") ||
               def.contains("全场景贯通") || def.contains("心智模型") ||
               def.contains("简单英文解释") || def.contains("中文解释") || def.contains("在这个语境下的意思") ||
               def.contains("Simple English") || def.contains("核心中文") || def.contains("AI 解析") ||
               (def.contains("：") && def.contains("\n"))
    }
}

public final class VocabularyStore: ObservableObject, @unchecked Sendable {
    public static let shared = VocabularyStore()

    @Published public var items: [VocabularyItem] = []
    @Published public var loadingItemIds: Set<UUID> = []
    @Published public var isBatchUpdatingAI: Bool = false
    @Published public var batchProgressText: String? = nil

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MacDict", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("vocabulary.json")
        load()
    }

    public func isSaved(word: String) -> Bool {
        let lower = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return items.contains { $0.word.lowercased() == lower }
    }

    public func toggleWord(
        word: String,
        phonetic: String?,
        definition: String,
        context: String?,
        sourceApp: String?,
        imageUrl: String? = nil
    ) {
        let lower = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = items.firstIndex(where: { $0.word.lowercased() == lower }) {
            items.remove(at: index)
        } else {
            let newItem = VocabularyItem(
                word: word,
                phonetic: phonetic,
                definition: definition,
                contextSentence: context,
                sourceAppName: sourceApp,
                imageUrl: imageUrl
            )
            items.insert(newItem, at: 0)
        }
        save()
    }

    public func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    /// 若单词已被收藏，用最新 AI 释义与插画无感更新
    public func updateDefinitionIfSaved(word: String, definition: String, imageUrl: String? = nil) {
        let lower = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = items.firstIndex(where: { $0.word.lowercased() == lower }) else { return }
        let trimmedDef = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDef.isEmpty else { return }
        var changed = false
        if items[index].definition != trimmedDef {
            items[index].definition = trimmedDef
            changed = true
        }
        if let img = imageUrl, !img.isEmpty, items[index].imageUrl != img {
            items[index].imageUrl = img
            changed = true
        }
        if changed {
            save()
        }
    }

    /// 单个单词异步调用大模型生成并替换为深度 AI 释义，并关联图解插画
    public func requestAIDefinition(for id: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let word = items[index].word
        let context = items[index].contextSentence
        await MainActor.run {
            _ = loadingItemIds.insert(id)
        }
        defer {
            Task { @MainActor in
                _ = loadingItemIds.remove(id)
            }
        }

        do {
            async let aiLookup = AIDictionarySource().lookup(word: word, context: context)
            async let imageLookup = WordImageService.shared.fetchImageAsync(for: word)

            let (res, (_, imgUrl)) = await (try aiLookup, imageLookup)
            if let aiText = res.aiAnalysis ?? res.definitions.first?.meaning, !aiText.isEmpty {
                await MainActor.run {
                    if let curIdx = items.firstIndex(where: { $0.id == id }) {
                        items[curIdx].definition = aiText
                        if let url = imgUrl {
                            items[curIdx].imageUrl = url
                        }
                        save()
                    }
                }
            }
        } catch {
            aLog("获取 AI 释义失败 [\(word)]: \(error.localizedDescription)", level: .error)
        }
    }

    /// 通过单词名称异步拉取 AI 深度释义
    public func requestAIDefinitionForWord(word: String, context: String? = nil) async {
        let lower = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let item = items.first(where: { $0.word.lowercased() == lower }) else { return }
        await requestAIDefinition(for: item.id)
    }

    /// 批量为生词本中的所有条目生成深度 AI 释义
    public func batchUpdateAllWithAI(forceAll: Bool = false) async {
        guard !isBatchUpdatingAI else { return }
        await MainActor.run {
            isBatchUpdatingAI = true
        }
        defer {
            Task { @MainActor in
                isBatchUpdatingAI = false
                batchProgressText = nil
            }
        }

        let targetItems: [VocabularyItem] = items.filter { item in
            if forceAll { return true }
            return !item.isAIDefinition
        }

        guard !targetItems.isEmpty else {
            await MainActor.run {
                batchProgressText = "所有生词均已是 AI 深度释义！"
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return
        }

        var completed = 0
        let total = targetItems.count

        for item in targetItems {
            if !isBatchUpdatingAI { break }
            let current = completed
            await MainActor.run {
                batchProgressText = "正在生成 AI 释义 (\(current + 1)/\(total)): \(item.word)..."
            }
            await requestAIDefinition(for: item.id)
            completed += 1
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        let finalCount = completed
        await MainActor.run {
            batchProgressText = "已完成全部 \(finalCount) 个生词的 AI 释义生成！"
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }

    public func stopBatchUpdate() {
        isBatchUpdatingAI = false
    }

    public func exportToCSV() -> URL? {
        var csv = "Word,Phonetic,Definition,Context,Date\n"
        for item in items {
            let escapedWord = "\"\(item.word.replacingOccurrences(of: "\"", with: "\"\""))\""
            let escapedPhonetic = "\"\(item.phonetic?.replacingOccurrences(of: "\"", with: "\"\"") ?? "")\""
            let escapedDef = "\"\(item.definition.replacingOccurrences(of: "\"", with: "\"\""))\""
            let escapedContext = "\"\(item.contextSentence?.replacingOccurrences(of: "\"", with: "\"\"") ?? "")\""
            let dateStr = ISO8601DateFormatter().string(from: item.dateAdded)
            csv += "\(escapedWord),\(escapedPhonetic),\(escapedDef),\(escapedContext),\(dateStr)\n"
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("MacDict_Vocabulary_\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([VocabularyItem].self, from: data) else {
            return
        }
        self.items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL)
    }
}
