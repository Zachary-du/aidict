import Foundation
import Combine
import SwiftUI

public struct HistoryItem: Identifiable, Codable, Sendable {
    public var id: UUID
    public var word: String
    public var phonetic: String?
    public var summary: String
    public var lastLookupDate: Date
    public var lookupCount: Int

    public init(
        id: UUID = UUID(),
        word: String,
        phonetic: String? = nil,
        summary: String = "",
        lastLookupDate: Date = Date(),
        lookupCount: Int = 1
    ) {
        self.id = id
        self.word = word
        self.phonetic = phonetic
        self.summary = summary
        self.lastLookupDate = lastLookupDate
        self.lookupCount = lookupCount
    }
}

public final class HistoryStore: ObservableObject, @unchecked Sendable {
    public static let shared = HistoryStore()

    @Published public var items: [HistoryItem] = []

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.dylan.MacDict.history", qos: .utility)

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MacDict", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    /// 记录一次查词历史（若已存在则移至顶部并累加查询次数）
    public func recordLookup(word: String, phonetic: String? = nil, summary: String = "") {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let lower = clean.lowercased()
            if let index = self.items.firstIndex(where: { $0.word.lowercased() == lower }) {
                var existing = self.items.remove(at: index)
                existing.lastLookupDate = Date()
                existing.lookupCount += 1
                if let p = phonetic, !p.isEmpty { existing.phonetic = p }
                if !summary.isEmpty { existing.summary = summary }
                self.items.insert(existing, at: 0)
            } else {
                let newItem = HistoryItem(
                    word: clean,
                    phonetic: phonetic,
                    summary: summary,
                    lastLookupDate: Date(),
                    lookupCount: 1
                )
                self.items.insert(newItem, at: 0)
            }

            // 保留最多 1000 条最近记录
            if self.items.count > 1000 {
                self.items = Array(self.items.prefix(1000))
            }
            self.save()
        }
    }

    public func lookupCount(for word: String) -> Int {
        let lower = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return items.first(where: { $0.word.lowercased() == lower })?.lookupCount ?? 1
    }

    public func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    public func clearAll() {
        items.removeAll()
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            return
        }
        self.items = decoded
    }

    private func save() {
        let currentItems = self.items
        queue.async { [fileURL] in
            guard let data = try? JSONEncoder().encode(currentItems) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
