import Foundation

/// Wiktionary REST API — free, no key, globally fast CDN
/// Endpoint: https://en.wiktionary.org/api/rest_v1/page/definition/{word}
public final class WiktionarySource: DictionarySource {
    public let id = "wiktionary"
    public let name = "Wiktionary"
    public let icon = "book.closed"
    public let priority = 2

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        return URLSession(configuration: cfg)
    }()

    public func lookup(word: String, context: String?) async throws -> DictionaryResult {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        let urlStr = "https://en.wiktionary.org/api/rest_v1/page/definition/\(encoded)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.setValue("MacDict/1.0 (macOS dictionary app)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // Wiktionary JSON: { "en": [ { "partOfSpeech": "...", "definitions": [ { "definition": "...", "examples": ["..."] } ] } ] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let enEntries = json["en"] as? [[String: Any]] else {
            return DictionaryResult(sourceId: id, sourceName: name, word: word, status: .failure("未找到"))
        }

        var definitions: [DefinitionItem] = []
        var audioURLStr: String? = nil
        var phonetic: String? = nil

        for entry in enEntries {
            let pos = entry["partOfSpeech"] as? String ?? ""
            let defs = entry["definitions"] as? [[String: Any]] ?? []

            for def in defs.prefix(3) {
                let raw = def["definition"] as? String ?? ""
                let clean = stripHTML(raw)
                guard !clean.isEmpty else { continue }

                let examplesRaw = def["examples"] as? [String] ?? []
                let examples = examplesRaw.prefix(2).map { stripHTML($0) }

                definitions.append(DefinitionItem(
                    partOfSpeech: pos,
                    meaning: clean,
                    examples: Array(examples)
                ))
            }

            // Extract audio URL
            if audioURLStr == nil,
               let phons = entry["pronunciations"] as? [[String: Any]] {
                for p in phons {
                    if let audioStr = p["audioFile"] as? String {
                        audioURLStr = audioStr
                        break
                    }
                    if phonetic == nil,
                       let trans = p["transcriptions"] as? [[String: Any]],
                       let t = trans.first?["transcription"] as? String {
                        phonetic = t
                    }
                }
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

    private func stripHTML(_ html: String) -> String {
        var result = html
        while let range = result.range(of: "<[^>]+>", options: .regularExpression) {
            result.replaceSubrange(range, with: "")
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
