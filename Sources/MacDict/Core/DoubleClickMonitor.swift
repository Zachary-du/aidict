import AppKit
import Foundation

/// 应用内双击查词监听器：
/// 严格仅限制在软件内部生效（主窗口、HUD 浮窗、AI 对话、影视原声等查词界面）。
/// 当用户在查词结果中看到任意生词时，直接双击该生词即可无缝跳转并查询，绝不监听或干扰外部网页、桌面及其他软件。
@MainActor
public final class DoubleClickMonitor {
    public static let shared = DoubleClickMonitor()

    private var localMonitor: Any?
    private var lastLookupTime: TimeInterval = 0
    private var lastLookupWord: String = ""

    private init() {}

    public func start() {
        stop()

        // 仅注册本地事件监听器（NSEvent.addLocalMonitorForEvents 仅对本应用自身的窗口生效，绝不影响其他应用）
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            if event.clickCount == 2 {
                self?.handleLocalDoubleClick(event: event)
            }
            return event
        }
    }

    public func stop() {
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
    }

    // MARK: - 词典应用内查词界面双击处理
    private func handleLocalDoubleClick(event: NSEvent) {
        guard let window = event.window else { return }

        // 如果双击发生在主窗口左侧侧边栏搜索框/历史列表内，不干扰用户日常的输入编辑
        if window === MainWindowController.shared.window {
            let loc = event.locationInWindow
            if loc.x < 240 {
                return
            }
        }

        let loc = event.locationInWindow

        // 稍微等待 35ms，确保 AppKit 文本渲染层与 field editor 彻底完成选区建立
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
            guard let self = self else { return }

            // 多级智能提取当前双击位置的词汇
            var candidate: String? = self.extractSelectedWord(from: window, at: loc)

            // 若选区未能提供，通过文本嗅探器在鼠标光标处提取
            if candidate == nil {
                let mousePos = NSEvent.mouseLocation
                if let sniffed = TextSniffer.shared.getTextAtCursor(screenPoint: mousePos) {
                    candidate = sniffed.word
                }
            }

            guard let raw = candidate, let word = Self.cleanLookupWord(raw) else { return }

            // 0.4 秒防抖：避免短时间内同一单词高频重复触发
            let now = ProcessInfo.processInfo.systemUptime
            if word.lowercased() == self.lastLookupWord.lowercased() && (now - self.lastLookupTime) < 0.4 {
                return
            }
            self.lastLookupWord = word
            self.lastLookupTime = now

            // 词典内部直接跳转查词
            if window === MainWindowController.shared.window {
                // 词典主窗口内双击：右侧详情和顶部搜索栏无缝跳转至该生词
                MainWindowController.shared.lookupFromDoubleClick(word)
            } else if window === HUDPanel.shared {
                // HUD 浮窗内双击：直接在 HUD 浮窗内查询该生词
                DictionaryEngine.shared.lookup(word: word, triggerSource: .manual)
            } else if window === MovieSceneWindowController.shared.window {
                // 影视原声窗口内双击：同步更新影视台词名场面与词典释义
                MovieSceneWindowController.shared.show(word: word)
                DictionaryEngine.shared.lookup(word: word, triggerSource: .manual)
            } else {
                // 其他软件内窗口双击：直接执行查词
                DictionaryEngine.shared.lookup(word: word, triggerSource: .manual)
            }
        }
    }

    // MARK: - 辅助：多层次精准提取窗口中被双击选中的文本
    private func extractSelectedWord(from window: NSWindow, at pointInWindow: NSPoint) -> String? {
        // 1. 优先检查当前聚焦的文本输入框或选区编辑器
        if let tv = window.firstResponder as? NSTextView {
            let range = tv.selectedRange()
            if range.location != NSNotFound && range.length > 0 {
                let str = (tv.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty {
                    return str
                }
            }
        }

        if let field = window.firstResponder as? NSTextField,
           let editor = field.currentEditor() as? NSTextView {
            let range = editor.selectedRange()
            if range.location != NSNotFound && range.length > 0 {
                let str = (editor.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty {
                    return str
                }
            }
        }

        // 2. 检查鼠标点击位置下的命中视图 (hitTest)
        if let hit = window.contentView?.hitTest(pointInWindow) {
            if let tv = hit as? NSTextView {
                let range = tv.selectedRange()
                if range.location != NSNotFound && range.length > 0 {
                    let str = (tv.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !str.isEmpty {
                        return str
                    }
                }
            }
            if let tf = hit as? NSTextField, let editor = tf.currentEditor() as? NSTextView {
                let range = editor.selectedRange()
                if range.location != NSNotFound && range.length > 0 {
                    let str = (editor.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !str.isEmpty {
                        return str
                    }
                }
            }
        }

        // 3. 递归查找窗口内容中任意具有有效选区的 NSTextView
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

        // 过滤网络链接
        if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") || cleaned.hasPrefix("file://") || cleaned.contains("://") {
            return nil
        }

        // 过滤文件路径
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

        // 长度上限限制 (避免整段文字误传入)
        guard cleaned.count <= 60 else {
            return nil
        }

        return cleaned
    }
}
