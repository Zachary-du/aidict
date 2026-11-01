import AppKit
import Foundation

/// 智能双击查词监听器：
/// 1. 应用内双击无缝跳转：在词典主窗口、HUD、AI 智能问答、影视原声等界面中，双击任意英文单词立即跳转查词。
/// 2. 全局双击快速取词：在 Safari、Chrome、备忘录、PDF、文档等任意第三方应用中双击英文单词，自动弹出 HUD 浮窗查词。
@MainActor
public final class DoubleClickMonitor {
    public static let shared = DoubleClickMonitor()

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastLookupTime: TimeInterval = 0
    private var lastLookupWord: String = ""

    private init() {}

    public func start() {
        stop()

        // 1. 本地事件监听（MacDict 自身所有窗口：主窗口、HUD、AI 问答、影视原声名场面等）
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            if event.clickCount == 2 {
                self?.handleLocalDoubleClick(event: event)
            }
            return event
        }

        // 2. 全局事件监听（系统其他所有第三方应用）
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            if event.clickCount == 2 {
                Task { @MainActor [weak self] in
                    self?.handleGlobalDoubleClick(event: event)
                }
            }
        }
    }

    public func stop() {
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
        if let gm = globalMonitor {
            NSEvent.removeMonitor(gm)
            globalMonitor = nil
        }
    }

    // MARK: - 应用内双击处理 (主窗口、HUD、AI 对话、影视原声等)
    private func handleLocalDoubleClick(event: NSEvent) {
        guard let window = event.window else { return }

        // 如果双击发生在主窗口的左侧侧边栏搜索框/历史区域内，不打扰用户的正常输入与编辑
        if window === MainWindowController.shared.window {
            let loc = event.locationInWindow
            if loc.x < 240 {
                return
            }
        }

        // 延迟 40ms，确保 AppKit 文本渲染层与 field editor 彻底完成选区构建
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self = self else { return }

            // 优先从具有选区的文本控件提取
            var candidate: String? = self.extractSelectedWord(from: window)

            // 若选区为空，通过辅助功能 / 光标位置嗅探单词
            if candidate == nil {
                let mousePos = NSEvent.mouseLocation
                if let sniffed = TextSniffer.shared.getTextAtCursor(screenPoint: mousePos) {
                    candidate = sniffed.word
                }
            }

            guard let raw = candidate, let word = Self.cleanLookupWord(raw) else { return }

            // 0.4 秒防抖：避免短时间内同一单词高频触发
            let now = ProcessInfo.processInfo.systemUptime
            if word.lowercased() == self.lastLookupWord.lowercased() && (now - self.lastLookupTime) < 0.4 {
                return
            }
            self.lastLookupWord = word
            self.lastLookupTime = now

            // 根据双击所在的界面执行对应跳转
            if window === MainWindowController.shared.window {
                // 主窗口内双击：直接在主窗口中无缝导航至该词条
                MainWindowController.shared.lookupFromDoubleClick(word)
            } else if window === HUDPanel.shared {
                // HUD 浮窗内双击：直接在浮窗内查词
                DictionaryEngine.shared.lookup(word: word, triggerSource: .manual)
            } else if window === MovieSceneWindowController.shared.window {
                // 影视原声窗口内双击：同步更新影视台词与词条释义
                MovieSceneWindowController.shared.show(word: word)
                DictionaryEngine.shared.lookup(word: word, triggerSource: .manual)
            } else {
                // 其他窗口内双击：全局查询
                DictionaryEngine.shared.lookup(word: word, triggerSource: .manual)
            }
        }
    }

    // MARK: - 全局第三方应用双击处理 (Safari/Chrome/Notes/Word/PDF等)
    private func handleGlobalDoubleClick(event: NSEvent) {
        guard SettingsStore.shared.isDoubleClickLookupEnabled else { return }

        // 避免干扰访达 Finder 中双击打开文件夹或运行应用的行为
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier == "com.apple.finder" {
            return
        }

        let mousePos = NSEvent.mouseLocation

        // 延迟 50ms 等待前台应用完成文本选区高亮
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }

            var sniffed = TextSniffer.shared.getSelectedTextFromFrontmostApp()
            if sniffed == nil {
                sniffed = TextSniffer.shared.getTextAtCursor(screenPoint: mousePos)
            }

            guard let s = sniffed, let word = Self.cleanLookupWord(s.word) else { return }

            // 单词长度限制：至少 2 个字母，杜绝无意义单字符误触
            guard word.count >= 2 else { return }

            let now = ProcessInfo.processInfo.systemUptime
            if word.lowercased() == self.lastLookupWord.lowercased() && (now - self.lastLookupTime) < 0.6 {
                return
            }
            self.lastLookupWord = word
            self.lastLookupTime = now

            // 弹出 HUD 浮窗并执行查询
            HUDPanel.shared.show(at: mousePos, source: .manual)
            DictionaryEngine.shared.lookup(word: word, context: s.contextSentence, sourceApp: s.sourceAppName)

            if SettingsStore.shared.playAudioOnLookup {
                AudioPlayer.shared.speak(text: word)
            }
        }
    }

    // MARK: - 辅助：从窗口中提取选中文本
    private func extractSelectedWord(from window: NSWindow) -> String? {
        if let tv = window.firstResponder as? NSTextView {
            let range = tv.selectedRange()
            if range.location != NSNotFound && range.length > 0 {
                let str = (tv.string as NSString).substring(with: range)
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        if let field = window.firstResponder as? NSTextField,
           let editor = field.currentEditor() as? NSTextView {
            let range = editor.selectedRange()
            if range.location != NSNotFound && range.length > 0 {
                let str = (editor.string as NSString).substring(with: range)
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
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
