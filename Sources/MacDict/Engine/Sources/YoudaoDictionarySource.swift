import Foundation

public final class YoudaoDictionarySource: DictionarySource, @unchecked Sendable {
    public let id = "youdao_dict"
    public let name = "有道双解 (词形/考纲)"
    public let icon = "network"
    public let priority = 3

    public init() {}

    public func lookup(word: String, context: String? = nil) async throws -> DictionaryResult {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://dict.youdao.com/jsonapi?q=\(encoded)") else {
            throw NSError(domain: "YoudaoDict", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效查询词"])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "YoudaoDict", code: 404, userInfo: [NSLocalizedDescriptionKey: "网络查询失败"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "YoudaoDict", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法解析有道数据"])
        }

        var phonetic: String? = nil
        var definitions: [DefinitionItem] = []
        var tags: [String] = []

        // 解析 ec (英汉双解)
        if let ec = json["ec"] as? [String: Any],
           let words = ec["word"] as? [[String: Any]],
           let firstWord = words.first {

            if let usphone = firstWord["usphone"] as? String, !usphone.isEmpty {
                phonetic = "美 [\(usphone)]"
            } else if let ukphone = firstWord["ukphone"] as? String, !ukphone.isEmpty {
                phonetic = "英 [\(ukphone)]"
            } else if let phone = firstWord["phone"] as? String, !phone.isEmpty {
                phonetic = "[\(phone)]"
            }

            if let trs = firstWord["trs"] as? [[String: Any]] {
                for tr in trs {
                    if let trList = tr["tr"] as? [[String: Any]],
                       let firstTr = trList.first,
                       let l = firstTr["l"] as? [String: Any],
                       let iList = l["i"] as? [String],
                       let meaning = iList.first {
                        // 分离词性与释义
                        let parts = meaning.components(separatedBy: " ")
                        if parts.count > 1 && parts[0].contains(".") {
                            definitions.append(DefinitionItem(partOfSpeech: parts[0], meaning: parts.dropFirst().joined(separator: " ")))
                        } else {
                            definitions.append(DefinitionItem(partOfSpeech: "释义", meaning: meaning))
                        }
                    }
                }
            }

            // 考试分类标签 (高考/四级/六级/考研/托福/雅思/GRE)
            if let examTypes = ec["exam_type"] as? [String] {
                tags.append(contentsOf: examTypes)
            }
        }

        // 如果 ec 为空，尝试取 web_trans 或 fallback suggest
        if definitions.isEmpty {
            if let webTrans = json["web_trans"] as? [String: Any],
               let webTransList = webTrans["web-translation"] as? [[String: Any]] {
                for item in webTransList.prefix(3) {
                    if let key = item["@key"] as? String,
                       let trans = item["trans"] as? [[String: Any]],
                       let firstT = trans.first,
                       let value = firstT["value"] as? String {
                        definitions.append(DefinitionItem(partOfSpeech: "网络释义", meaning: "\(key): \(value)"))
                    }
                }
            }
        }

        guard !definitions.isEmpty else {
            throw NSError(domain: "YoudaoDict", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到有道释义"])
        }

        let audioURL = "https://dict.youdao.com/dictvoice?audio=\(encoded)&type=2"

        return DictionaryResult(
            sourceId: id,
            sourceName: name,
            word: trimmed,
            phonetic: phonetic,
            audioURL: audioURL,
            definitions: definitions,
            tags: tags,
            status: .success
        )
    }
}
