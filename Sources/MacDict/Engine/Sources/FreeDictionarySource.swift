import Foundation

public final class FreeDictionarySource: DictionarySource, @unchecked Sendable {
    public let id = "free_dictionary_api"
    public let name = "Free Dictionary (英英)"
    public let icon = "character.book.closed"
    public let priority = 2

    public init() {}

    public func lookup(word: String, context: String? = nil) async throws -> DictionaryResult {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else {
            throw NSError(domain: "FreeDict", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效查询词"])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "FreeDict", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到英英释义"])
        }

        struct PhoneticResponse: Decodable {
            let text: String?
            let audio: String?
        }

        struct DefDetail: Decodable {
            let definition: String
            let example: String?
        }

        struct MeaningResponse: Decodable {
            let partOfSpeech: String
            let definitions: [DefDetail]
        }

        struct EntryResponse: Decodable {
            let word: String
            let phonetic: String?
            let phonetics: [PhoneticResponse]?
            let meanings: [MeaningResponse]
        }

        let entries = try JSONDecoder().decode([EntryResponse].self, from: data)
        guard let first = entries.first else {
            throw NSError(domain: "FreeDict", code: 404, userInfo: [NSLocalizedDescriptionKey: "内容为空"])
        }

        // 分别提取美式(US)和英式(UK)音标与音频
        var phonetic: String? = first.phonetic
        var phonetic_uk: String? = nil
        var audioURL: String? = nil    // US mp3
        var audioURL_uk: String? = nil // UK mp3

        if let list = first.phonetics {
            for p in list {
                let audio = p.audio ?? ""
                let lower = audio.lowercased()
                // Free Dictionary API 命名规律: -us.mp3 / -uk.mp3 / en-us / en-gb
                let isUK = lower.contains("-uk") || lower.contains("en-gb") || lower.contains("/gb/")

                if isUK {
                    if phonetic_uk == nil, let t = p.text, !t.isEmpty { phonetic_uk = t }
                    if audioURL_uk == nil && !audio.isEmpty { audioURL_uk = audio }
                } else {
                    // US 或未指定 → 归为美式
                    if phonetic == nil, let t = p.text, !t.isEmpty { phonetic = t }
                    if audioURL == nil && !audio.isEmpty { audioURL = audio }
                }
            }
        }

        var defItems: [DefinitionItem] = []
        for m in first.meanings {
            for d in m.definitions.prefix(3) {
                var examples: [String] = []
                if let ex = d.example, !ex.isEmpty {
                    examples.append(ex)
                }
                defItems.append(DefinitionItem(
                    partOfSpeech: m.partOfSpeech,
                    meaning: d.definition,
                    examples: examples
                ))
            }
        }

        return DictionaryResult(
            sourceId: id,
            sourceName: name,
            word: first.word,
            phonetic: phonetic,
            phonetic_uk: phonetic_uk,
            audioURL: audioURL,
            audioURL_uk: audioURL_uk,
            definitions: defItems,
            status: .success
        )
    }
}
