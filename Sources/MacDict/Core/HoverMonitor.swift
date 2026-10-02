import AppKit
import Combine
import CoreServices

@MainActor
public final class HoverMonitor {
    public static let shared = HoverMonitor()

    private var mouseMonitor: Any?
    private var hoverTimer: Timer?
    private var lastMousePoint: NSPoint = .zero
    private var lastLookupPoint: NSPoint = .zero
    private var lastWordLookedUp: String = ""

    // 关闭抑制机制：用户手动关闭后，鼠标必须移开指定距离才会再次触发
    private var isDismissedByUser: Bool = false
    private var dismissPoint: NSPoint = .zero
    private var suppressedWord: String = ""

    private init() {}

    public func start() {
        stop()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMouseMoved(to: NSEvent.mouseLocation)
            }
        }
    }

    public func stop() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    /// 当用户点击关闭按钮、按 Esc 或点击外部关闭面板时调用
    public func notifyDismissed(at point: NSPoint, word: String) {
        isDismissedByUser = true
        dismissPoint = point
        suppressedWord = word
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func handleMouseMoved(to point: NSPoint) {
        lastMousePoint = point
        hoverTimer?.invalidate()

        // 0. 若用户正在拖拽缩放浮窗，绝不干扰
        if HUDPanel.shared.isResizing { return }

        // 1. 手动关闭抑制检查：若鼠标尚未移出关闭区域 (20像素内)，不触发悬停（防闪烁但不影响连续查词）
        if isDismissedByUser {
            let dist = hypot(point.x - dismissPoint.x, point.y - dismissPoint.y)
            if dist < 20 {
                return
            } else {
                isDismissedByUser = false
                suppressedWord = ""
            }
        }

        // 2. 浮窗已显现时的鼠标移动处理
        if HUDPanel.shared.isVisible {
            // 关键：若正处于 AI 问答对话模式，绝不因为鼠标移动而关闭！必须由用户显式点击关闭按钮
            if HUDPanel.shared.isInAIChat {
                return
            }

            // 关键：若浮窗是由快捷键划词或手动触发的，绝对不要因为鼠标移动而关闭！
            // 用户需要自由移动鼠标进入面板、滚动查看释义、点击发音或加入生词本
            if HUDPanel.shared.currentTriggerSource == .manual {
                return
            }

            // 若是由悬停触发的：鼠标在浮窗内、伴侣卡内、两卡片之间联合通道内、或原词附近，保持展开
            let safeArea = HUDPanel.shared.frame.insetBy(dx: -35, dy: -35)
            let companionArea = HUDCompanionPanel.shared.isVisible ? HUDCompanionPanel.shared.frame.insetBy(dx: -35, dy: -35) : .zero
            let unionArea = HUDCompanionPanel.shared.isVisible ? HUDPanel.shared.frame.union(HUDCompanionPanel.shared.frame).insetBy(dx: -35, dy: -35) : safeArea
            let wordArea = CGRect(x: lastLookupPoint.x - 40, y: lastLookupPoint.y - 40, width: 80, height: 80)
            if safeArea.contains(point) || companionArea.contains(point) || unionArea.contains(point) || wordArea.contains(point) {
                return
            }

            // 只有当鼠标移开原词超过 100 像素且不在安全区时，才淡出
            let dist = hypot(point.x - lastLookupPoint.x, point.y - lastLookupPoint.y)
            if dist > 100 {
                HUDPanel.shared.dismiss()
            }
            return
        }

        // 3. 检查悬停开关总控
        guard SettingsStore.shared.isHoverLookupEnabled else { return }

        // 4. 若启用了按住修饰键悬停 (如 Option 键)，未按键时直接忽略
        if SettingsStore.shared.hoverRequiresOptionKey {
            if !NSEvent.modifierFlags.contains(.option) {
                return
            }
        }

        // 5. 启动防抖定时器
        let delay = SettingsStore.shared.hoverDelay
        hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.executeHoverCheck(at: point)
            }
        }
    }

    private func executeHoverCheck(at point: NSPoint) {
        guard SettingsStore.shared.isHoverLookupEnabled else { return }
        if HUDPanel.shared.isVisible && (HUDPanel.shared.frame.contains(point) || HUDPanel.shared.isInAIChat) { return }
        if isDismissedByUser { return }
        if HUDPanel.shared.isResizing { return }

        Task { [weak self] in
            guard let self = self else { return }

            let sniffed = await Task.detached(priority: .userInitiated) {
                TextSniffer.shared.getTextAtCursor(screenPoint: point)
            }.value

            guard let sniffed = sniffed else { return }

            let cleanWord = sniffed.word.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: .punctuationCharacters)
            guard cleanWord.count >= 2 else { return }

            // 核心改进：静默本地词典权威预检！
            // 若该词不存在于系统牛津或本地柯林斯词典，判定为非字典词（如代码、符号、杂质），静默放弃，绝不弹窗！
            guard self.isKnownWord(cleanWord) else { return }

            // 避免在同一个位置或刚被关闭的单词上反复触发
            if cleanWord.lowercased() == self.suppressedWord.lowercased() &&
               hypot(point.x - self.dismissPoint.x, point.y - self.dismissPoint.y) < 50 {
                return
            }

            if cleanWord.lowercased() == self.lastWordLookedUp.lowercased() &&
               (HUDPanel.shared.isVisible || hypot(point.x - self.lastLookupPoint.x, point.y - self.lastLookupPoint.y) < 15) {
                return
            }

            self.lastWordLookedUp = cleanWord
            self.lastLookupPoint = point

            HUDPanel.shared.show(at: point, source: .hover)
            DictionaryEngine.shared.lookup(
                word: cleanWord,
                context: sniffed.contextSentence,
                sourceApp: sniffed.sourceAppName,
                triggerSource: .hover
            )
        }
    }

    // MARK: - 本地词典静默预检

    /// 预检单词是否真实存在于本地权威词典中，确保悬停不乱弹窗
    private func isKnownWord(_ word: String) -> Bool {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        
        // 1. 基础形态与长度校验
        guard clean.count >= 2 && clean.count <= 35 else { return false }
        
        // 过滤纯数字或纯标点
        if clean.allSatisfy({ $0.isNumber || $0.isPunctuation }) { return false }
        
        // 必须包含字母或汉字
        let hasLetterOrCJK = clean.contains { char in
            char.isLetter || (char.unicodeScalars.first?.value ?? 0) >= 0x4E00
        }
        guard hasLetterOrCJK else { return false }

        // 2. 本地原生牛津词典快速预检 (<0.3ms)
        let range = CFRangeMake(0, (clean as NSString).length)
        if DCSCopyTextDefinition(nil, clean as CFString, range) != nil {
            return true
        }

        // 3. 本地已导入的自定义词典（如柯林斯 8 版 SQLite）快速预检 (<0.3ms)
        if CustomDictionaryStore.shared.lookup(word: clean) != nil {
            return true
        }

        return false
    }
}
