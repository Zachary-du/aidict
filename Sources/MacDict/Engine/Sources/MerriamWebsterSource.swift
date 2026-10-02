import Foundation

/// Merriam-Webster Collegiate Dictionary API
/// Free API key at: https://dictionaryapi.com (1,000 req/day)
/// Set your key in Settings → 词典管理 → Merriam-Webster API Key
public final class MerriamWebsterSource: DictionarySource {
    public let id = "merriam_webster"
    public let name = "Merriam-Webster"
    public let icon = "m.book.closed"
    public let priority = 3

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        return URLSession(configuration: cfg)
    }()

    public func lookup(word: String, context: String?) async throws -> DictionaryResult {
        let apiKey = SettingsStore.shared.merriamWebsterAPIKey
        guard !apiKey.isEmpty else {
            return DictionaryResult(
                sourceId: id, sourceName: name, word: word,
                status: .failure("未设置 Merriam-Webster API Key。请在设置 → 词典管理 中填写免费 Key。")
            )
        }

        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        let urlStr = "https://www.dictionaryapi.com/api/v3/references/collegiate/json/\(encoded)?key=\(apiKey)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.setValue("MacDict/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // MW returns array of entry dicts or strings (spelling suggestions)
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !array.isEmpty else {
            return DictionaryResult(sourceId: id, sourceName: name, word: word, status: .failure("未找到"))
        }

        var definitions: [DefinitionItem] = []
        var phonetic: String? = nil
        var audioURLStr: String? = nil

        for entry in array.prefix(3) {
            let pos = entry["fl"] as? String ?? ""

            // Phonetic
            if phonetic == nil,
               let hwi = entry["hwi"] as? [String: Any],
               let prs = hwi["prs"] as? [[String: Any]],
               let pr = prs.first?["mw"] as? String {
                phonetic = "/\(pr)/"
            }

            // Audio URL
            if audioURLStr == nil,
               let hwi = entry["hwi"] as? [String: Any],
               let prs = hwi["prs"] as? [[String: Any]],
               let sound = prs.first?["sound"] as? [String: Any],
               let audio = sound["audio"] as? String {
                let subdir: String
                if audio.hasPrefix("bix") { subdir = "bix" }
                else if audio.hasPrefix("gg") { subdir = "gg" }
                else if let first = audio.first, first.isNumber { subdir = "number" }
                else { subdir = String(audio.prefix(1)) }
                audioURLStr = "https://media.merriam-webster.com/audio/prons/en/us/mp3/\(subdir)/\(audio).mp3"
            }

            // Short definitions
            if let shortDefs = entry["shortdef"] as? [String] {
                for def in shortDefs.prefix(4) {
                    definitions.append(DefinitionItem(
                        partOfSpeech: pos,
                        meaning: def,
                        examples: []
                    ))
                }
                break
            }
        }

        if definitions.isEmpty {
            return DictionaryResult(sourceId: id, sourceName: name, word: word, status: .failure("未找到"))
        }

        return DictionaryResult(
            sourceId: id,
            sourceName: name,
            word: word,
            phonetic: phonetic,
            audioURL: audioURLStr,
            definitions: definitions,
            status: .success
        )
    }
}
