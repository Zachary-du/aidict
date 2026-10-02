import Foundation

public final class CollinsDictionarySource: DictionarySource, @unchecked Sendable {
    public let id = "collins_cobuild"
    public let name = "柯林斯高阶 (COBUILD)"
    public let icon = "character.book.closed.fill"
    public let priority = 1

    public init() {}

    public func lookup(word: String, context: String? = nil) async throws -> DictionaryResult {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wordCount = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        if wordCount >= 6 || trimmed.hasSuffix(".") || trimmed.hasSuffix("?") || trimmed.hasSuffix("!") {
            throw NSError(domain: "Collins", code: 404, userInfo: [NSLocalizedDescriptionKey: "整句翻译请查看 AI 语境分析"])
        }

        let cleanWord = trimmed.replacingOccurrences(of: " ", with: "-")
        guard let encoded = cleanWord.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://www.collinsdictionary.com/dictionary/english/\(encoded)") else {
            throw NSError(domain: "Collins", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效查询词"])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Collins", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到柯林斯释义"])
        }

        return try parseCollinsHTML(html, queryWord: trimmed)
    }

    private func parseCollinsHTML(_ html: String, queryWord: String) throws -> DictionaryResult {
        // 1. 词头
        let headword = firstMatch(in: html, pattern: #"<span class="orth">([^<]+)</span>"#)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? queryWord

        // 2. 音标
        let pronRaw = firstMatch(in: html, pattern: #"<span class="pron">([^<]+)</span>"#)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: " /[]()"))
        let formattedPron = pronRaw.flatMap { !$0.isEmpty ? "/\($0)/" : nil }

        // 3. 音频 (仅限词头原声 hwd_sounds，严禁例句发音，且必须与目标词匹配)
        var ukAudio: String? = nil
        var usAudio: String? = nil
        var rootWord: String? = nil
        let cleanQuery = queryWord.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let audioTagMatches = allMatches(in: html, pattern: #"(<[^>]*class="[^"]*audio_play_button[^"]*"[^>]*>)"#)
        for tag in audioTagMatches {
            guard let mp3Raw = firstMatch(in: tag, pattern: #"data-src-mp3="([^"]+)""#) else { continue }
            let clean = cleanAudioURL(mp3Raw)
            let lower = clean.lowercased()
            // 过滤包含 exa 或 example 的例句发音
            guard !lower.contains("exa") && !lower.contains("example") else { continue }

            // 严格校验音频标签归属词 (例如 title="Pronunciation for durable")
            if let titleWord = firstMatch(in: tag, pattern: #"title="Pronunciation for ([^"]+)""#)?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                if titleWord != cleanQuery {
                    rootWord = titleWord
                    continue
                }
            }

            // 优先捕获带有 hwd_sounds 标记或标准语言代码的词头录音
            if lower.contains("en_gb") || lower.contains("uk") || tag.contains("en_GB") || lower.contains("hwd_sounds") {
                if ukAudio == nil { ukAudio = clean }
            } else if lower.contains("en_us") || lower.contains("us") || tag.contains("en_US") {
                if usAudio == nil { usAudio = clean }
            }
        }
        if usAudio == nil { usAudio = ukAudio }
        if ukAudio == nil { ukAudio = usAudio }

        // 4. 词频与标签 (例如 COBUILD 频次 band 3 -> ●●●)
        var tags: [String] = []
        if let rw = rootWord, rw != cleanQuery {
            tags.append("词根: \(rw)")
        } else if headword.lowercased() != cleanQuery {
            tags.append("词根: \(headword)")
        }

        if let bandStr = firstMatch(in: html, pattern: #"data-band="([1-5])""#),
           let band = Int(bandStr) {
            let dots = String(repeating: "●", count: band)
            tags.append("COBUILD 频次 \(dots)")
        }

        // 词形变化 (如 Word forms: plural recommendations)
        if let wordFormsRaw = firstMatch(in: html, pattern: #"<span class="form inflected_forms">([\s\S]*?)</span>"#) {
            let cleanForms = stripHTMLTags(wordFormsRaw).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanForms.isEmpty {
                tags.append(cleanForms)
            }
        }

        // CEFR 等级 (如 B2)
        if let cefr = firstMatch(in: html, pattern: #"<span class="level">([^<]+)</span>"#)?
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            tags.append("CEFR \(cefr)")
        }

        // 5. 提取 COBUILD 释义条目
        var defItems: [DefinitionItem] = []
        let senseBlocks = extractHomBlocks(html: html)

        for (index, blockHTML) in senseBlocks.enumerated() {
            // 词性与语法 (如 variable noun [oft with poss])
            let posRaw = firstMatch(in: blockHTML, pattern: #"<span class="gramGrp">([\s\S]*?)</span>"#)
            var cleanPos = posRaw.flatMap { stripHTMLTags($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            if cleanPos.isEmpty {
                cleanPos = firstMatch(in: blockHTML, pattern: #"<span class="pos">([^<]+)</span>"#)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "COBUILD"
            }

            // 释义正文 (整句释义)
            guard let defRaw = firstMatch(in: blockHTML, pattern: #"<div class="def">([\s\S]*?)</div>"#) else {
                continue
            }
            let cleanDef = stripHTMLTags(defRaw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanDef.isEmpty else { continue }

            // 例句与原厂母语者录音棚音频
            var exampleItems: [ExampleItem] = []
            let exMatches = allMatches(in: blockHTML, pattern: #"(<div class="cit type-example[^"]*"[\s\S]*?</div>)"#)
            if !exMatches.isEmpty {
                for citHTML in exMatches.prefix(4) {
                    guard let quoteRaw = firstMatch(in: citHTML, pattern: #"<span class="quote">([\s\S]*?)</span>"#) else { continue }
                    let cleanEx = stripHTMLTags(quoteRaw).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanEx.isEmpty else { continue }
                    var audio: String? = nil
                    if let rawAudio = firstMatch(in: citHTML, pattern: #"data-src-mp3="([^"]+)""#) {
                        audio = cleanAudioURL(rawAudio)
                    }
                    exampleItems.append(ExampleItem(text: cleanEx, audioURL: audio))
                }
            } else {
                let fallbackMatches = allMatches(in: blockHTML, pattern: #"<div class="cit type-example">[\s\S]*?<span class="quote">([\s\S]*?)</span>"#)
                for ex in fallbackMatches.prefix(4) {
                    let cleanEx = stripHTMLTags(ex).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanEx.isEmpty {
                        exampleItems.append(ExampleItem(text: cleanEx, audioURL: nil))
                    }
                }
            }

            defItems.append(DefinitionItem(
                partOfSpeech: cleanPos,
                meaning: "\(index + 1). \(cleanDef)",
                exampleItems: exampleItems
            ))
        }

        guard !defItems.isEmpty else {
            throw NSError(domain: "Collins", code: 404, userInfo: [NSLocalizedDescriptionKey: "未解析到柯林斯有效释义"])
        }

        return DictionaryResult(
            sourceId: id,
            sourceName: name,
            word: headword,
            phonetic: formattedPron,
            phonetic_uk: formattedPron,
            audioURL: usAudio,
            audioURL_uk: ukAudio,
            definitions: defItems,
            tags: tags,
            status: .success
        )
    }

    private func cleanAudioURL(_ raw: String) -> String {
        if raw.hasPrefix("http") {
            return raw
        } else if raw.hasPrefix("//") {
            return "https:" + raw
        } else {
            return "https://www.collinsdictionary.com" + (raw.hasPrefix("/") ? "" : "/") + raw
        }
    }

    private func extractHomBlocks(html: String) -> [String] {
        var blocks: [String] = []
        let pattern = #"<div class="hom">[\s\S]*?</div>\s*(?=<div class="hom"|</div\s*>\s*</div\s*>|\z)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))
        for m in matches {
            blocks.append(nsString.substring(with: m.range))
        }
        return blocks
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsString = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsString.length)),
              match.numberOfRanges > 1 else { return nil }
        return nsString.substring(with: match.range(at: 1))
    }

    private func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        var results: [String] = []
        for m in matches where m.numberOfRanges > 1 {
            results.append(nsString.substring(with: m.range(at: 1)))
        }
        return results
    }

    private func stripHTMLTags(_ str: String) -> String {
        var res = str.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        res = res.replacingOccurrences(of: "&nbsp;", with: " ")
        res = res.replacingOccurrences(of: "&amp;", with: "&")
        res = res.replacingOccurrences(of: "&quot;", with: "\"")
        res = res.replacingOccurrences(of: "&#39;", with: "'")
        res = res.replacingOccurrences(of: "&apos;", with: "'")
        res = res.replacingOccurrences(of: "&lt;", with: "<")
        res = res.replacingOccurrences(of: "&gt;", with: ">")
        return res.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
