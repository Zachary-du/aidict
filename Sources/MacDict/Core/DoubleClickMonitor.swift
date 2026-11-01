import AppKit
import Foundation

/// 智能应用内双击查词监听器：
/// 严格仅限制在词典软件内部生效（主窗口、HUD 浮窗、AI 问答对话、影视原声等查词界面）。
/// 当用户在 AI 解析、例句或释义中看到任意生词时，双击该单词即可瞬间跳转并查询该词，绝不监听或干扰外部任何软件。
@MainActor
public final class DoubleClickMonitor {
    public static let shared = DoubleClickMonitor()

    private var localMonitor: Any?
    private var lastLookupTime: TimeInterval = 0
    private var lastLookupWord: String = ""

    private init() {}

    public func start() {
        stop()

        // 监听应用内鼠标按下与抬起事件（针对 NSTextField/NSTextView 双击选词可能在 mouseDown 或 mouseUp 触发）
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            if event.clickCount == 2 {
                self?.handleLocalDoubleClick(event: event)
            }
            return event
        }
        aLog("DoubleClickMonitor 已启动（严格限制在 MacDict 应用内窗口生效）")
    }

    public func stop() {
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
    }

    /// 记录最近一次已处理的查词，用于与 UI 控件内部双击互相同步防抖
    public func recordLookup(word: String) {
        lastLookupWord = word
        lastLookupTime = ProcessInfo.processInfo.systemUptime
    }

    // MARK: - 词典应用内查词界面双击处理
    private func handleLocalDoubleClick(event: NSEvent) {
        guard let window = event.window ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }

        let loc = event.locationInWindow

        // 判断是否为主窗口
        let isMainWindow = (window === MainWindowController.shared.window || window.title.contains("MacDict"))

        // 如果双击发生在主窗口最左侧搜索框输入区域（x < 200 且位于顶部搜索栏），不干扰用户正常的打字编辑
        if isMainWindow && loc.x < 200 && loc.y > (window.frame.height - 70) {
            return
        }

        // 稍微等待 30ms，确保 AppKit 文本渲染层与 field editor 彻底完成双击选词高亮
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self = self else { return }

            // 多级提取当前双击位置的词汇
            var candidate: String? = self.extractSelectedWord(from: window, at: loc)

            // 若选区未能提取到，通过光标屏幕坐标直接嗅探当前鼠标悬停的单词
            if candidate == nil {
                let mousePos = NSEvent.mouseLocation
                if let sniffed = TextSniffer.shared.getTextAtCursor(screenPoint: mousePos) {
                    candidate = sniffed.word
                }
            }

            guard let raw = candidate, let word = Self.cleanLookupWord(raw) else {
                return
            }

            // 0.4 秒防抖：避免同一双击的 mouseDown 与 mouseUp 产生二次重复查询
            let now = ProcessInfo.processInfo.systemUptime
            if word.lowercased() == self.lastLookupWord.lowercased() && (now - self.lastLookupTime) < 0.4 {
                return
            }
            self.lastLookupWord = word
            self.lastLookupTime = now

            aLog("🎯 [双击查词] 成功捕获词典内双击生词: '\(word)' (来源窗口: \(window.title))")

            // 根据双击所在的界面执行对应跳转
            if isMainWindow {
                MainWindowController.shared.lookupFromDoubleClick(word)
            } else if window === HUDPanel.shared || window is HUDPanel {
                DictionaryEngine.shared.lookup(word: word, triggerSource: .manual)
            } else if window === MovieSceneWindowController.shared.window {
                MovieSceneWindowController.shared.show(word: word)
                DictionaryEngine.shared.lookup(word: word, triggerSource: .manual)
            } else {
                DictionaryEngine.shared.lookup(word: word, triggerSource: .manual)
            }
        }
    }

    // MARK: - 辅助：多层次精准提取窗口中被双击选中的文本
    private func extractSelectedWord(from window: NSWindow, at pointInWindow: NSPoint) -> String? {
        // 1. 优先检查窗口全局 fieldEditor（AppKit 对任何可选中/可编辑控件创建的统一编辑器）
        if let editor = window.fieldEditor(false, for: nil) as? NSTextView {
            let range = editor.selectedRange()
            if range.location != NSNotFound && range.length > 0 {
                let str = (editor.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty {
                    return str
                }
            }
        }

        // 2. 检查窗口当前第一响应者 (NSTextView)
        if let tv = window.firstResponder as? NSTextView {
            let range = tv.selectedRange()
            if range.location != NSNotFound && range.length > 0 {
                let str = (tv.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty {
                    return str
                }
            }
        }

        // 3. 检查鼠标点击位置下的命中视图 (hitTest)
        if let hit = window.contentView?.hitTest(pointInWindow) {
            // A. 命中本身为 NSTextView
            if let tv = hit as? NSTextView {
                let range = tv.selectedRange()
                if range.location != NSNotFound && range.length > 0 {
                    let str = (tv.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !str.isEmpty {
                        return str
                    }
                }
            }
            // B. 命中为 NSTextField（例如 SwiftUI.SelectionTextField）
            if let tf = hit as? NSTextField {
                if let editor = (window.fieldEditor(false, for: tf) as? NSTextView) ?? (tf.currentEditor() as? NSTextView) {
                    let range = editor.selectedRange()
                    if range.location != NSNotFound && range.length > 0 {
                        let str = (editor.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !str.isEmpty {
                            return str
                        }
                    }
                }
                // 若未进入编辑态但为独立单词文本块（例如单独一行只显示 "anchor"）
                let rawVal = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawVal.isEmpty {
                    if let cleaned = Self.cleanLookupWord(rawVal), !cleaned.contains(" ") {
                        return cleaned
                    }
                }
            }
        }

        // 4. 递归查找窗口内容中任意具有选区的 NSTextView
        if let contentView = window.contentView {
            if let selected = findActiveSelectedText(in: contentView) {
                return selected
            }
        }

        return nil
    }

    private func findActiveSelectedText(in view: NSView) -> String? {
        if let tv = view as? NSTextView {
            let range = tv.selectedRange()
            if range.location != NSNotFound && range.length > 0 {
                let str = (tv.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty {
                    return str
                }
            }
        }
        for sub in view.subviews {
            if let found = findActiveSelectedText(in: sub) {
                return found
            }
        }
        return nil
    }

    // MARK: - 单词清洗与有效性校验
    public static func cleanLookupWord(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 剥离外层常见标点、序号、引号、括号、列表符号等
        let punc = CharacterSet(charactersIn: "\"'\"“”‘’()[]{}<>.,;:!?`~*#_\\/|•◦1234567890-")
        let cleaned = trimmed.trimmingCharacters(in: punc).trimmingCharacters(in: .whitespaces)

        guard !cleaned.isEmpty else { return nil }

        // 过滤网络链接与文件路径
        if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") || cleaned.hasPrefix("file://") || cleaned.contains("://") {
            return nil
        }
        if cleaned.hasPrefix("/") || cleaned.contains("/") || cleaned.contains("\\") {
            return nil
        }

        // 过滤纯数字
        if cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) {
            return nil
        }

        // 必须包含有效字母或汉字
        guard cleaned.rangeOfCharacter(from: .letters) != nil else {
            return nil
        }

        // 长度上限限制
        guard cleaned.count <= 60 else {
            return nil
        }

        return cleaned
    }
}
