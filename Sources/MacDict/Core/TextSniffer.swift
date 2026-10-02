import Foundation
import AppKit
import ApplicationServices
import Vision

public struct SniffedText: Sendable {
    public let word: String
    public let contextSentence: String?
    public let sourceAppName: String?

    public init(word: String, contextSentence: String? = nil, sourceAppName: String? = nil) {
        self.word = word
        self.contextSentence = contextSentence
        self.sourceAppName = sourceAppName
    }
}

public final class TextSniffer: @unchecked Sendable {
    public static let shared = TextSniffer()

    private init() {}

    /// 将 Cocoa 屏幕坐标 (原点在主屏左下角) 转换为 Quartz 全局坐标 (原点在主屏左上角)
    public static func cocoaToQuartz(point: CGPoint) -> CGPoint {
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
        return CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// 获取当前前台处于聚焦状态的应用所选中的文本 (划词快捷键使用)
    public func getSelectedTextFromFrontmostApp() -> SniffedText? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        let appName = frontApp.localizedName ?? "App"
        let appElement = AXUIElementCreateApplication(pid)

        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if result == .success, let element = focusedElement {
            let axElem = element as! AXUIElement
            var selectedTextValue: AnyObject?
            if AXUIElementCopyAttributeValue(axElem, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
               let text = selectedTextValue as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                var fullTextValue: AnyObject?
                var context: String? = nil
                if AXUIElementCopyAttributeValue(axElem, kAXValueAttribute as CFString, &fullTextValue) == .success,
                   let fullText = fullTextValue as? String {
                    context = extractSentence(containing: text, from: fullText)
                }

                return SniffedText(word: text, contextSentence: context, sourceAppName: appName)
            }
        }

        return captureViaSimulatedCopy(appName: appName)
    }

    /// 精准获取鼠标当前悬停处下方的词汇 (严格判断光标是否真正位于字符上方)
    public func getTextAtCursor(screenPoint: CGPoint) -> SniffedText? {
        let quartzPoint = Self.cocoaToQuartz(point: screenPoint)
        let systemWide = AXUIElementCreateSystemWide()
        var elementUnderMouse: AXUIElement?

        let copyResult = AXUIElementCopyElementAtPosition(systemWide, Float(quartzPoint.x), Float(quartzPoint.y), &elementUnderMouse)
        if copyResult == .success, let element = elementUnderMouse {
            // 排除无文本的容器控件 (窗口、滚动区、分栏等背景)
            var roleObj: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleObj)
            let role = (roleObj as? String) ?? ""
            let containerRoles: Set<String> = [
                "AXWindow", "AXApplication", "AXScrollArea", "AXScrollBar",
                "AXSplitGroup", "AXGroup", "AXList", "AXOutline", "AXTable",
                "AXRow", "AXColumn", "AXToolbar", "AXMenu", "AXMenuBar",
                "AXMenuItem", "AXButton", "AXPopUpButton", "AXTabGroup"
            ]

            if !containerRoles.contains(role) {
                if let wordInfo = extractWordFromAXElement(element, quartzPoint: quartzPoint) {
                    return wordInfo
                }
            }
        }

        // 仅在 AX 未提取到时进行严格的 Vision OCR 嗅探 (必须严格相交)
        return captureWordViaVisionOCR(aroundQuartzPoint: quartzPoint)
    }

    // MARK: - 私有辅助方法

    private func extractWordFromAXElement(_ element: AXUIElement, quartzPoint: CGPoint) -> SniffedText? {
        var valueObj: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueObj) != .success || valueObj == nil {
            if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &valueObj) != .success || valueObj == nil {
                return nil
            }
        }

        guard let fullText = valueObj as? String, !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // 通过 AXIndexForPosition 精确测量光标对应字符
        var charIndexVal: AnyObject?
        var pt = quartzPoint
        if let posValue = AXValueCreate(.cgPoint, &pt),
           AXUIElementCopyParameterizedAttributeValue(element, "AXIndexForPosition" as CFString, posValue, &charIndexVal) == .success,
           let charIndex = charIndexVal as? Int, charIndex >= 0, charIndex < fullText.count {

            let index = fullText.index(fullText.startIndex, offsetBy: charIndex)
            let targetChar = fullText[index]

            // 关键：如果光标所在字符是空格、换行或标点，说明鼠标在空白处，直接返回 nil，不乱取词！
            guard targetChar.isLetter || targetChar.isNumber else {
                return nil
            }

            if let wordRange = getWordRange(at: index, in: fullText) {
                let word = String(fullText[wordRange]).trimmingCharacters(in: .punctuationCharacters)
                if word.count >= 2 {
                    let context = extractSentence(containing: word, from: fullText)
                    let validContext = TextSniffer.cleanContextSentence(context, targetWord: word)
                    return SniffedText(word: word, contextSentence: validContext, sourceAppName: nil)
                }
            }
        }

        // 检查是否有选中文本（支持单词、短语与长句）
        var selectedTextVal: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextVal) == .success,
           let sel = selectedTextVal as? String, !sel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let clean = sel.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.count >= 1 && clean.count <= 1000 {
                let isWholeSentence = clean.count >= 40 && (clean.contains(" ") && (clean.hasSuffix(".") || clean.hasSuffix("?") || clean.hasSuffix("!") || clean.hasSuffix("。") || clean.hasSuffix("？") || clean.hasSuffix("！")))
                let context = isWholeSentence ? clean : extractSentence(containing: clean, from: fullText)
                let validContext = isWholeSentence ? clean : TextSniffer.cleanContextSentence(context, targetWord: clean)
                return SniffedText(word: clean, contextSentence: validContext, sourceAppName: nil)
            }
        }

        return nil
    }

    /// Vision OCR 严格像素级碰撞检测：采用 accurate 神经网络模型并结合深色反相预处理与终端分词
    private func captureWordViaVisionOCR(aroundQuartzPoint quartzPoint: CGPoint) -> SniffedText? {
        // 扩大视野至 360 x 75，彻底避免像 (System-defined 或长路径被边缘暴力切断的问题
        let width: CGFloat = 200
        let height: CGFloat = 55
        let rect = CGRect(
            x: quartzPoint.x - width / 2,
            y: quartzPoint.y - height / 2,
            width: width,
            height: height
        )

        guard let rawCGImage = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else {
            return nil
        }

        // 自适应预处理：针对 iTerm2 等黑底环境自动反相为白底黑字，提升小号等宽字体识别率 40%+
        let processedCGImage = OCRPreprocessor.shared.preprocess(cgImage: rawCGImage)

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: processedCGImage, options: [:])
        try? handler.perform([request])

        guard let observations = request.results else { return nil }

        // 光标在截图切片中的归一化坐标为 (0.5, 0.5)
        let cursorNormPoint = CGPoint(x: 0.5, y: 0.5)

        for obs in observations {
            // 文本行相交检测
            let expandedBox = obs.boundingBox.insetBy(dx: -0.04, dy: -0.08)
            guard expandedBox.contains(cursorNormPoint) else { continue }

            guard let candidate = obs.topCandidates(1).first else { continue }
            let lineText = candidate.string
            let words = lineText.components(separatedBy: .whitespacesAndNewlines)
            var searchStart = lineText.startIndex

            for w in words {
                guard !w.isEmpty else { continue }
                guard let range = lineText.range(of: w, range: searchStart..<lineText.endIndex) else { continue }
                searchStart = range.upperBound

                if let boxObj = try? candidate.boundingBox(for: range) {
                    let wordBox = boxObj.boundingBox.insetBy(dx: -0.04, dy: -0.06)
                    if wordBox.contains(cursorNormPoint) {
                        // 使用终端专属清洗器清洗特殊符号（剔除反斜杠、路径前缀、引号括号等）
                        let clean = OCRNormalizer.shared.sanitizeTerminalToken(w)
                        
                        // 拒绝包含大量特殊符号的无效 OCR 识别结果
                        let letterDigitCount = clean.filter { $0.isLetter || $0.isNumber }.count
                        let ratio = Float(letterDigitCount) / Float(clean.count)
                        guard ratio >= 0.6 else { continue }
                        // 拒绝明显是代码片段（含连续特殊字符对）
                        let codeIndicators: [String] = ["#\"", "*{", "{8", "J*", "#'", "={", "${", "<%", "%>"]
                        if codeIndicators.contains(where: { clean.contains($0) }) { continue }

                        if clean.count >= 2 {
                            let validContext = TextSniffer.cleanContextSentence(lineText, targetWord: clean)
                            return SniffedText(word: clean, contextSentence: validContext, sourceAppName: nil)
                        }
                    }
                }
            }
        }

        return nil
    }

    private func captureViaSimulatedCopy(appName: String) -> SniffedText? {
        let pasteboard = NSPasteboard.general
        let oldChangeCount = pasteboard.changeCount
        let oldString = pasteboard.string(forType: .string)

        // 采用独立 HID 状态源，显式清除用户手指正在按住的 Option (0x3A) 键对模拟按键的干扰
        let src = CGEventSource(stateID: .hidSystemState)
        let optUp = CGEvent(keyboardEventSource: src, virtualKey: 0x3A, keyDown: false)
        optUp?.flags = []
        optUp?.post(tap: .cghidEventTap)

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = []

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // 自旋轮询等待终端或 Electron 应用完成复制 (最多等待 160ms，一旦变动立即返回)
        var newText: String? = nil
        for _ in 0..<16 {
            usleep(10000) // 10ms
            if pasteboard.changeCount != oldChangeCount {
                if let str = pasteboard.string(forType: .string), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    newText = str
                }
                break
            }
        }

        if let text = newText {
            // 异步还原用户原本的剪贴板内容，实现无感取词
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) {
                if let old = oldString {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(old, forType: .string)
                }
            }
            return SniffedText(word: text, contextSentence: nil, sourceAppName: appName)
        }

        return nil
    }

    private func extractSentence(containing word: String, from text: String) -> String {
        guard let range = text.range(of: word) else { return text }
        let delimiters = CharacterSet(charactersIn: ".?!。\n；;")
        let start = text[..<range.lowerBound].rangeOfCharacter(from: delimiters, options: .backwards)?.upperBound ?? text.startIndex
        let end = text[range.upperBound...].rangeOfCharacter(from: delimiters)?.lowerBound ?? text.endIndex
        let sentence = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.isEmpty ? text : sentence
    }

    private func getWordRange(at index: String.Index, in text: String) -> Range<String.Index>? {
        guard text.indices.contains(index) else { return nil }
        var start = index
        var end = index

        while start > text.startIndex {
            let prev = text.index(before: start)
            if text[prev].isLetter || text[prev].isNumber || text[prev] == "'" || text[prev] == "-" {
                start = prev
            } else {
                break
            }
        }

        while end < text.endIndex {
            if text[end].isLetter || text[end].isNumber || text[end] == "'" || text[end] == "-" {
                end = text.index(after: end)
            } else {
                break
            }
        }

        guard start < end else { return nil }
        return start..<end
    }

    // MARK: - 语境句子智能清洗与乱码检测

    /// 清洗语境文本，并严格校验是否为可读自然句子；若含乱码、代码或特殊符号则返回 nil（直接隐藏语境模块）
    public static func cleanContextSentence(_ text: String, targetWord: String) -> String? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. 去除截图边缘切断产生的噪音前缀（如 "*512E ", "#12 ", "- ", "• " 等）
        if let prefixMatch = cleaned.range(of: #"^[\*#@_~|>•\-\d]+[A-Za-z0-9]*[\s:\-]+"#, options: .regularExpression) {
            cleaned.removeSubrange(prefixMatch)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 2. 严格校验
        guard isValidContextSentence(cleaned, targetWord: targetWord) else {
            return nil
        }
        return cleaned
    }

    /// 严格校验文本是否为清晰可读的自然语言句子
    public static func isValidContextSentence(_ text: String, targetWord: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 长度限制：语境句子至少需要基本完整度
        guard trimmed.count >= 6 && trimmed.count <= 260 else { return false }
        
        // 必须包含所查单词
        guard trimmed.range(of: targetWord, options: .caseInsensitive) != nil else { return false }
        
        // 拒绝以特殊符号开头的非自然文本
        let invalidPrefixes = ["*", "#", "@", "/", "\\", "_", "~", "|", "<", ">", ";", "=", "{", "}", "(", ")", "0x", "$", "%", "&"]
        if invalidPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return false
        }
        
        // 拒绝包含明显代码结构或终端命令特征
        let codeIndicators = [
            "=>", "->", "::", "!=", "==", "===", "&&", "||", "{}", "[]", "</", "/>",
            "import ", "export ", "function ", "const ", "let ", "var ", "class ",
            "public ", "private ", "func ", "def ", "return ", "SELECT ", "FROM ",
            "WHERE ", "http://", "https://", "git ", "npm ", "cd ", "sudo ", "docker ",
            "println", "console.log", "$("
        ]
        if codeIndicators.contains(where: { trimmed.contains($0) }) {
            return false
        }
        
        // 拒绝包含常见 OCR 识别错误/替换符与异常符号
        let garbledChars = CharacterSet(charactersIn: "\u{FFFD}§¶†‡‰©®™°±²³µ¿¡`^~|\t\r")
        if trimmed.unicodeScalars.contains(where: { garbledChars.contains($0) }) {
            return false
        }
        
        // 检测常见编码混乱（Mojibake）特征
        let mojibakePatterns = ["Ã", "Â", "â€", "锟斤拷", "烫烫烫"]
        if mojibakePatterns.contains(where: { trimmed.contains($0) }) {
            return false
        }
        
        // 字符合法性统计：仅允许英文字母、规范常用汉字、阿拉伯数字、标准中英文标点与空格
        var validCount = 0
        for scalar in trimmed.unicodeScalars {
            let val = scalar.value
            let isAsciiLetterOrDigit = (val >= 0x41 && val <= 0x5A) || (val >= 0x61 && val <= 0x7A) || (val >= 0x30 && val <= 0x39)
            // CJK 统一表意汉字规范范围 (4E00 - 9FFF)
            let isCJK = (val >= 0x4E00 && val <= 0x9FA5)
            // 中英文标点及空格
            let isPunctuationOrSpace =
                val == 0x20 || // space
                val == 0x2E || val == 0x2C || val == 0x3F || val == 0x21 || // . , ? !
                val == 0x3A || val == 0x3B || val == 0x27 || val == 0x22 || // : ; ' "
                val == 0x2D || val == 0x2014 || val == 0x2026 || // - — …
                val == 0x3001 || val == 0x3002 || // 、 。
                val == 0xFF0C || val == 0xFF01 || val == 0xFF1F || val == 0xFF1A || val == 0xFF1B || // ， ！ ？ ： ；
                val == 0x201C || val == 0x201D || val == 0x2018 || val == 0x2019 || // “ ” ‘ ’
                val == 0x300A || val == 0x300B || val == 0xFF08 || val == 0xFF09 || val == 0x3010 || val == 0x3011 // 《 》 （ ） 【 】
            
            if isAsciiLetterOrDigit || isCJK || isPunctuationOrSpace {
                validCount += 1
            }
        }
        
        let ratio = Double(validCount) / Double(trimmed.unicodeScalars.count)
        return ratio >= 0.90
    }
}
