import Foundation
import AppKit
import CoreServices

public struct CorrectedWord: Sendable {
    public let word: String
    public let originalWord: String?
    public let wasCorrected: Bool

    public init(word: String, originalWord: String? = nil, wasCorrected: Bool = false) {
        self.word = word
        self.originalWord = originalWord
        self.wasCorrected = wasCorrected
    }
}

public final class OCRNormalizer: @unchecked Sendable {
    public static let shared = OCRNormalizer()

    private let checker = NSSpellChecker.shared
    private let commonOCRMappings: [(String, String)] = [
        ("opE", "opt"),
        ("Eion", "tion"),
        ("lc", "r"),
        ("cl", "d"),
        ("rn", "m"),
        ("vv", "w"),
        ("1l", "ll")
    ]

    private init() {}

    /// 清洗终端中的特殊符号（路径分隔符、bash转义斜杠、引号、括号、前缀点号等）
    public func sanitizeTerminalToken(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 剥离两端包裹符号：括号、方括号、单双引号、反引号、冒号、逗号、分号
        let wrapperSet = CharacterSet(charactersIn: "()[]{}<>\"'`.,:;\\/$%#*&?!~")
        text = text.trimmingCharacters(in: wrapperSet)

        // 处理终端中的转义空格反斜杠 (例如 Download\ trash -> Download)
        if text.hasSuffix("\\") {
            text.removeLast()
        }
        text = text.replacingOccurrences(of: "\\", with: "")

        // 处理路径分隔 (例如 ds/Download 或 /etc/uhttpd.conf)
        if text.contains("/") {
            let parts = text.components(separatedBy: "/").map { $0.trimmingCharacters(in: wrapperSet) }.filter { $0.count >= 2 }
            if let longest = parts.max(by: { $0.count < $1.count }) {
                text = longest
            }
        }

        // 处理扩展名 (例如 .torrent)
        if text.hasPrefix(".") {
            text = String(text.dropFirst()).trimmingCharacters(in: wrapperSet)
        }

        // 最终有效性校验：字母/数字占比必须 >= 55%
        let letterCount = text.filter { $0.isLetter || $0.isNumber }.count
        if text.count > 0 && Float(letterCount) / Float(text.count) < 0.55 {
            return ""
        }
        // 单词过长（>25字符且不含空格）时，取最长字母段（防止终端长路径混入）
        if !text.contains(" ") && text.count > 25 {
            let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 }
            text = tokens.max(by: { $0.count < $1.count }) ?? ""
        }

        return text
    }

    /// 统一规范化用户查词文本（适用于单词、短语、整句等所有主动查询输入，严禁截断）
    public func normalizeQueryText(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        // 去除两端包裹符号：中英文引号、书名号、最外层括号等
        let outerWrappers = CharacterSet(charactersIn: "\"\"''“”‘’「」『』《》〈〉()（）[]【】{}")
        text = text.trimmingCharacters(in: outerWrappers)

        // 将内部连续的多换行、多Tab与连续多空格收敛为规范的单空格
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 安全上限保护（1000 字符）
        if text.count > 1000 {
            text = String(text.prefix(1000))
        }

        return text
    }

    /// 清洗词汇，彻底移除自动拼写纠错猜词，完全尊重用户的原始输入与单词（例如 emby 等）
    public func normalizeAndCorrect(_ word: String) -> CorrectedWord {
        let cleaned = normalizeQueryText(word)
        return CorrectedWord(word: cleaned, originalWord: nil, wasCorrected: false)
    }

    private func isValidDictionaryWord(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let range = CFRangeMake(0, (trimmed as NSString).length)
        return DCSCopyTextDefinition(nil, trimmed as CFString, range) != nil
    }

    private func isCloseWord(_ a: String, _ b: String) -> Bool {
        let aChars = Array(a.lowercased())
        let bChars = Array(b.lowercased())
        let diff = abs(aChars.count - bChars.count)
        guard diff <= 2 else { return false }

        var matches = 0
        let minLen = min(aChars.count, bChars.count)
        for i in 0..<minLen {
            if aChars[i] == bChars[i] { matches += 1 }
        }
        return Float(matches) / Float(minLen) >= 0.65
    }
}
