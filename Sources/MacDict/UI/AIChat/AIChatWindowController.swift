import AppKit
import SwiftUI

@MainActor
public final class AIChatWindowController: NSObject, NSWindowDelegate {
    public static let shared = AIChatWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    /// 显示或激活 AI 问答对话窗口
    /// - Parameters:
    ///   - word: 待探讨的词条或短语
    ///   - context: 捕获的句子语境
    ///   - initialQuestion: 可选的直接自动发送的问题
    public func show(word: String? = nil, context: String? = nil, initialQuestion: String? = nil) {
        if window == nil || window?.isVisible == false {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "MacDict AI 智能问答对话"
            win.titlebarAppearsTransparent = true
            win.toolbarStyle = .unifiedCompact
            win.minSize = NSSize(width: 460, height: 500)
            win.center()
            win.setFrameAutosaveName("MacDictAIChatWindow")
            win.contentView = NSHostingView(rootView: AIChatView())
            win.isReleasedWhenClosed = false
            win.delegate = self
            self.window = win
        }

        // 载入词汇与初始化提问
        if let w = word?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty {
            AIChatService.shared.startChat(word: w, context: context, followUpQuestion: initialQuestion)
        } else if let q = initialQuestion, !q.isEmpty {
            AIChatService.shared.sendMessage(q)
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func toggleWindow() {
        if let win = window, win.isVisible {
            win.orderOut(nil)
        } else {
            show(word: DictionaryEngine.shared.currentWord, context: DictionaryEngine.shared.contextSentence)
        }
    }

    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        // 保留窗口实例以复用状态，或按需清理
    }
}
