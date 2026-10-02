import Foundation

public final class LongmanDictionarySource: DictionarySource, @unchecked Sendable {
    public let id = "longman"
    public let name = "朗文当代 (LDOCE)"
    public let icon = "book.closed.fill"
    public let priority = 0

    public init() {}

    public func lookup(word: String, context: String? = nil) async throws -> DictionaryResult {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wordCount = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        if wordCount >= 6 || trimmed.hasSuffix(".") || trimmed.hasSuffix("?") || trimmed.hasSuffix("!") {
            throw NSError(domain: "Longman", code: 404, userInfo: [NSLocalizedDescriptionKey: "整句翻译请查看 AI 语境分析"])
        }

        let cleanWord = trimmed.replacingOccurrences(of: " ", with: "-")
        guard let encoded = cleanWord.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://www.ldoceonline.com/dictionary/\(encoded)") else {
            throw NSError(domain: "Longman", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效查询词"])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Longman", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到朗文释义"])
        }

        return try parseLongmanHTML(html, queryWord: trimmed)
    }

    private func parseLongmanHTML(_ html: String, queryWord: String) throws -> DictionaryResult {
        // 1. 提取词头与音节拆分 (如 rec·om·men·da·tion)
        let hyphenation = firstMatch(in: html, pattern: #"<span class="HYPHENATION">([^<]+)</span>"#)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hwd = firstMatch(in: html, pattern: #"<span class="HWD">([^<]+)</span>"#)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayWord = hyphenation ?? hwd ?? queryWord

        // 2. 词性
        let pos = firstMatch(in: html, pattern: #"<span class="POS">([^<]+)</span>"#)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "noun"

        // 3. 音标 (IPA)
        var ukPron: String? = nil
        if let rawPron = firstMatch(in: html, pattern: #"<span class="PRON">((?:<span[^>]*>[\s\S]*?</span>|[^<])*)</span>"#) {
            let cleanPron = stripHTMLTags(rawPron).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanPron.isEmpty { ukPron = cleanPron }
        }
        var usPron: String? = nil
        if let rawUs = firstMatch(in: html, pattern: #"<span class="AMEVARPRON">[\s\S]*?<span class="PRON">((?:<span[^>]*>[\s\S]*?</span>|[^<])*)</span>"#) {
            let cleanUs = stripHTMLTags(rawUs).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanUs.isEmpty { usPron = cleanUs }
        }
        if usPron == nil { usPron = ukPron }

        // 4. 音频 URL (严格限定词头发音 breProns / ameProns，严禁捕获例句 exaProns 音频)
        var ukAudio: String? = nil
        var usAudio: String? = nil

        // 优先从词头发音图标提取
        if let breMatch = firstMatch(in: html, pattern: #"class="[^"]*brefile[^"]*"[^>]*data-src-mp3="([^"]+)""#) {
            let clean = cleanAudioURL(breMatch)
            if !clean.contains("exaProns") { ukAudio = clean }
        } else if let breUrl = firstMatch(in: html, pattern: #"https?://[^"'\s]+/breProns/[^"'\s]+\.mp3[^"'\s]*"#) {
            ukAudio = cleanAudioURL(breUrl)
        }

        if let ameMatch = firstMatch(in: html, pattern: #"class="[^"]*amefile[^"]*"[^>]*data-src-mp3="([^"]+)""#) {
            let clean = cleanAudioURL(ameMatch)
            if !clean.contains("exaProns") { usAudio = clean }
        } else if let ameUrl = firstMatch(in: html, pattern: #"https?://[^"'\s]+/ameProns/[^"'\s]+\.mp3[^"'\s]*"#) {
            usAudio = cleanAudioURL(ameUrl)
        }

        // 防御词根重定向导致的音频错配
        let isRedirected = displayWord.lowercased() != queryWord.lowercased()
        if isRedirected {
            let queryClean = queryWord.lowercased().replacingOccurrences(of: "-", with: "")
            if let us = usAudio, !us.lowercased().contains(queryClean) {
                usAudio = nil
            }
            if let uk = ukAudio, !uk.lowercased().contains(queryClean) {
                ukAudio = nil
            }
        }

        // 5. 核心词频标签 (如 S3, W3, ★★☆, 3000)
        var tags: [String] = []
        if isRedirected {
            tags.append("词根: \(displayWord)")
        }
        // S1-S3, W1-W3 核心高频词标（严格大写）
        let swMatches = allMatches(in: html, pattern: #"\b([SW][1-3])\b"#)
        for sw in swMatches {
            let upper = sw.uppercased()
            if sw == upper && !tags.contains(upper) {
                tags.append(upper)
            }
        }
        // 词频星级 / LEVEL
        let levelMatches = allMatches(in: html, pattern: #"class="[^"]*LEVEL[^"]*"[^>]*title="([^"]+)""#)
        for lv in levelMatches where !tags.contains(lv) {
            tags.append(lv)
        }
        if let starSpan = firstMatch(in: html, pattern: #"<span class="LEVEL">([^<]+)</span>"#) {
            let stars = starSpan.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stars.isEmpty && !tags.contains(stars) { tags.append(stars) }
        }

        // 6. 释义与例句 (Sense 块)
        var defItems: [DefinitionItem] = []
        let senseBlocks = extractSenseBlocks(html: html)

        for (index, senseHTML) in senseBlocks.enumerated() {
            // 释义序号与导引词 (Signpost)
            let signpost = firstMatch(in: senseHTML, pattern: #"<span class="SIGNPOST">([^<]+)</span>"#)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 释义正文
            guard let rawDef = firstMatch(in: senseHTML, pattern: #"<span class="DEF">([\s\S]*?)</span>"#) else {
                continue
            }
            let cleanDef = stripHTMLTags(rawDef).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanDef.isEmpty else { continue }

            var fullDef = cleanDef
            if let sp = signpost, !sp.isEmpty {
                fullDef = "[\(sp)] " + cleanDef
            }

            // 提取例句与原厂母语者棚录原声音频
            var exampleItems: [ExampleItem] = []
            // 模式 1: speaker 位于 EXAMPLE 内部 (例如 <span class="EXAMPLE"><span data-src-mp3="..." class="speaker..."> </span>text</span>)
            let richPattern1 = #"<span class="EXAMPLE">\s*<span[^>]*data-src-mp3="([^"]+)"[^>]*>[\s\S]*?</span>([\s\S]*?)</span>"#
            // 模式 2: speaker 位于 EXAMPLE 紧邻外部 (例如 <span data-src-mp3="..." class="speaker..."> </span>\s*<span class="EXAMPLE">text</span>)
            let richPattern2 = #"<span[^>]*data-src-mp3="([^"]+)"[^>]*>[\s\S]*?</span>\s*<span class="EXAMPLE">([\s\S]*?)</span>"#

            if let regex = try? NSRegularExpression(pattern: richPattern1, options: [.caseInsensitive]) {
                let ns = senseHTML as NSString
                let matches = regex.matches(in: senseHTML, range: NSRange(location: 0, length: ns.length))
                for m in matches.prefix(4) {
                    if m.numberOfRanges >= 3 {
                        let audioRaw = ns.substring(with: m.range(at: 1))
                        let textRaw = ns.substring(with: m.range(at: 2))
                        let cleanText = stripHTMLTags(textRaw).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanText.isEmpty {
                            exampleItems.append(ExampleItem(text: cleanText, audioURL: cleanAudioURL(audioRaw)))
                        }
                    }
                }
            }

            if exampleItems.isEmpty, let regex = try? NSRegularExpression(pattern: richPattern2, options: [.caseInsensitive]) {
                let ns = senseHTML as NSString
                let matches = regex.matches(in: senseHTML, range: NSRange(location: 0, length: ns.length))
                for m in matches.prefix(4) {
                    if m.numberOfRanges >= 3 {
                        let audioRaw = ns.substring(with: m.range(at: 1))
                        let textRaw = ns.substring(with: m.range(at: 2))
                        let cleanText = stripHTMLTags(textRaw).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanText.isEmpty {
                            exampleItems.append(ExampleItem(text: cleanText, audioURL: cleanAudioURL(audioRaw)))
                        }
                    }
                }
            }

            // 模式 3: 普通无音频例句回退
            if exampleItems.isEmpty {
                let plainMatches = allMatches(in: senseHTML, pattern: #"<span class="EXAMPLE">([\s\S]*?)</span>"#)
                for ex in plainMatches.prefix(4) {
                    let cleanEx = stripHTMLTags(ex).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanEx.isEmpty {
                        exampleItems.append(ExampleItem(text: cleanEx, audioURL: nil))
                    }
                }
            }

            defItems.append(DefinitionItem(
                partOfSpeech: pos,
                meaning: "\(index + 1). \(fullDef)",
                exampleItems: exampleItems
            ))
        }

        guard !defItems.isEmpty else {
            throw NSError(domain: "Longman", code: 404, userInfo: [NSLocalizedDescriptionKey: "未解析到有效释义"])
        }

        return DictionaryResult(
            sourceId: id,
            sourceName: name,
            word: displayWord,
            phonetic: usPron != nil ? "/\(usPron!)/" : nil,
            phonetic_uk: ukPron != nil ? "/\(ukPron!)/" : nil,
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
            return "https://www.ldoceonline.com" + (raw.hasPrefix("/") ? "" : "/") + raw
        }
    }

    private func extractSenseBlocks(html: String) -> [String] {
        var blocks: [String] = []
        let pattern = #"<span class="Sense"[\s\S]*?</span>\s*(?=<span class="Sense"|</span\s*>\s*</span\s*>|\z)"#
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
        res = res.replacingOccurrences(of: "&lt;", with: "<")
        res = res.replacingOccurrences(of: "&gt;", with: ">")
        return res.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
