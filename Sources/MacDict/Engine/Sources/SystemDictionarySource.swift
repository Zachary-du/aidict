import Foundation
import CoreServices

public final class SystemDictionarySource: DictionarySource, @unchecked Sendable {
    public let id = "system_oxford"
    public let name = "系统词典 (Oxford)"
    public let icon = "apple.logo"
    public let priority = 1

    public init() {}

    public func lookup(word: String, context: String? = nil) async throws -> DictionaryResult {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "SystemDictionary", code: -1, userInfo: [NSLocalizedDescriptionKey: "单词为空"])
        }

        let range = CFRangeMake(0, (trimmed as NSString).length)
        guard let defRef = DCSCopyTextDefinition(nil, trimmed as CFString, range) else {
            throw NSError(domain: "SystemDictionary", code: 404, userInfo: [NSLocalizedDescriptionKey: "系统词典中未找到该词条"])
        }

        let fullDefinition = defRef.takeRetainedValue() as String
        let cleaned = fullDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw NSError(domain: "SystemDictionary", code: 404, userInfo: [NSLocalizedDescriptionKey: "释义内容为空"])
        }

        // 提取音标（系统词典常见格式 /.../ 或 |...| 或 [...]）
        var phonetic: String? = nil
        let phoneticPattern = #"[/|\[]([^/|\]\n]{1,35})[/|\]]"#
        if let regex = try? NSRegularExpression(pattern: phoneticPattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let r = Range(match.range(at: 1), in: cleaned) {
            let ph = String(cleaned[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !ph.isEmpty {
                phonetic = "/\(ph)/"
            }
        }

        // 解析多条释义或直接作为原生完整排版呈现
        let lines = cleaned.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var defItems: [DefinitionItem] = []
        var currentPOS = "释义"

        for line in lines.prefix(15) {
            if line.starts(with: "▶") || line.starts(with: "•") || line.contains(";") {
                defItems.append(DefinitionItem(partOfSpeech: currentPOS, meaning: line))
            } else if line.count < 10 && (line.contains("n.") || line.contains("v.") || line.contains("adj.") || line.contains("adv.")) {
                currentPOS = line
            }
        }

        if defItems.isEmpty {
            defItems.append(DefinitionItem(partOfSpeech: "完整释义", meaning: cleaned))
        }

        return DictionaryResult(
            sourceId: id,
            sourceName: name,
            word: trimmed,
            phonetic: phonetic,
            audioURL: nil,
            definitions: defItems,
            rawText: cleaned,
            status: .success
        )
    }
}
