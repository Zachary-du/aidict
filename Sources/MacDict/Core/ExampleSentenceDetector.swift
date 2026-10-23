import Foundation

/// 智能识别并提取 AI 回答中的英文例句（严格过滤纯中文、词性、音标、核心释义等非例句行）
public struct ExampleSentenceDetector {
    /// 从单行文本中提取可朗读的纯英文例句；若非英文例句行则返回 nil
    public static func extractEnglishSentence(from rawLine: String) -> String? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 排除常见非例句标记行
        let excludedPrefixes = [
            "中文对照", "中文翻译", "中文：", "中文:", "译文", "翻译",
            "词性", "音标", "核心释义", "核心中文", "【语境】", "语境",
            "【1.", "【2.", "【3.", "1. 词性", "2. 核心", "3. 最地道"
        ]
        for exp in excludedPrefixes {
            if trimmed.hasPrefix(exp) {
                return nil
            }
        }

        var clean = trimmed

        // 剥离可能的前缀标号：如 "• ", "- ", "* " 或 "1. ", "2. "
        if clean.hasPrefix("• ") || clean.hasPrefix("- ") || clean.hasPrefix("* ") {
            clean = String(clean.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else if let first = clean.first, first.isNumber {
            if let dotIdx = clean.firstIndex(of: ".") {
                let prefix = clean[..<dotIdx]
                if Int(prefix) != nil {
                    clean = clean[clean.index(after: dotIdx)...].trimmingCharacters(in: .whitespaces)
                }
            }
        }

        // 匹配并剥离例句前缀
        let prefixes = [
            "例句:", "例句：", "例句 ", "例句",
            "Example:", "Example：", "Example ",
            "Ex:", "Ex：", "e.g.", "eg:", "eg："
        ]
        for p in prefixes {
            if clean.hasPrefix(p) {
                clean = String(clean.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // 剥离尾部紧随的中文括号，例如 "The kitchen is clean. (厨房很干净)"
        if let parenIdx = clean.firstIndex(of: "(") ?? clean.firstIndex(of: "（") {
            clean = String(clean[..<parenIdx]).trimmingCharacters(in: .whitespaces)
        }

        // 剥离可能包含的 "——" 或 " -- " 中文对照
        if let dashIdx = clean.range(of: " —— ")?.lowerBound ?? clean.range(of: " -- ")?.lowerBound {
            clean = String(clean[..<dashIdx]).trimmingCharacters(in: .whitespaces)
        }

        // 剥离外层引号
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))

        // 统计英文单词数
        let words = clean.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard words.count >= 2 else { return nil }

        let latinCount = clean.filter { $0.isLetter && $0.isASCII }.count
        let chineseCount = clean.filter { ("\u{4E00}"..."\u{9FFF}").contains($0) }.count

        // 必须英文字母占主导（且至少包含 6 个字母），绝非中文行
        guard latinCount >= 6 && latinCount > chineseCount else {
            return nil
        }

        return clean
    }
}
