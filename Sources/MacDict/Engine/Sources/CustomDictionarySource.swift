import Foundation

// MARK: - 单本自定义词典的独立查词源
// 每本导入的词典在词典列表中独立成行，有自己的名称、排序和启用开关

public final class SingleCustomDictionarySource: DictionarySource, @unchecked Sendable {
    public let dictId: String      // 对应 dict_meta.id (UUID)
    public let dictName: String    // 对应 dict_meta.name（文件名）
    public let dictFormat: String  // "MDX" / "JSON" / "TSV" 等
    public let entryCount: Int

    // DictionarySource 协议要求
    public var id: String { "custom_dict_\(dictId)" }
    public var name: String { dictName }
    public var icon: String { iconForFormat(dictFormat) }
    public var priority: Int { 6 }

    public init(meta: CustomDictionaryStore.DictMeta) {
        self.dictId = meta.id
        self.dictName = meta.name
        self.dictFormat = meta.format
        self.entryCount = meta.entryCount
    }

    public func lookup(word: String, context: String?) async throws -> DictionaryResult {
        if let def = CustomDictionaryStore.shared.lookupInDict(word: word, dictId: dictId) {
            var extractedPhonetic: String? = nil
            if let match = def.range(of: #"(\[[^\]\n]{1,35}\]|/[^/\n]{1,35}/)"#, options: .regularExpression) {
                let raw = String(def[match]).trimmingCharacters(in: CharacterSet(charactersIn: "[]/"))
                if !raw.isEmpty {
                    extractedPhonetic = "/\(raw)/"
                }
            }
            return DictionaryResult(
                sourceId: id,
                sourceName: dictName,
                word: word,
                phonetic: extractedPhonetic,
                definitions: [DefinitionItem(partOfSpeech: "释义", meaning: def)],
                status: .success
            )
        }
        return DictionaryResult(
            sourceId: id,
            sourceName: dictName,
            word: word,
            status: .failure("未找到")
        )
    }

    private func iconForFormat(_ fmt: String) -> String {
        switch fmt.uppercased() {
        case "MDX":         return "book.closed"
        case "JSON":        return "doc.text"
        case "TSV", "CSV":  return "tablecells"
        default:            return "books.vertical"
        }
    }
}

// MARK: - 兼容旧代码的空壳（已不直接使用，保留避免其他地方引用出错）
public final class CustomDictionarySource: DictionarySource, @unchecked Sendable {
    public let id = "custom_dict"
    public let name = "自定义词典"
    public let icon = "books.vertical"
    public let priority = 6

    public init() {}

    public func lookup(word: String, context: String?) async throws -> DictionaryResult {
        // 这个合并源已被各独立词典源取代，正常不会被调用
        return DictionaryResult(
            sourceId: id, sourceName: name, word: word,
            status: .failure("已改为独立词典源模式")
        )
    }
}
