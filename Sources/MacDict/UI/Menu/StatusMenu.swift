import AppKit
import SwiftUI

@MainActor
public final class StatusMenuController: NSObject {
    public static let shared = StatusMenuController()

    private var statusItem: NSStatusItem?
    private var vocabWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private var singleClickTimer: Timer?

    private override init() {
        super.init()
    }

    public func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "character.book.closed.fill", accessibilityDescription: "MacDict")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// 点击状态栏图标：区分双击（打开主界面）与单击/右键（弹出操作菜单）
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            popUpStatusMenu()
            return
        }

        // 1. 右键单击或 Control+单击：立即弹出菜单，不延时
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            singleClickTimer?.invalidate()
            singleClickTimer = nil
            popUpStatusMenu()
            return
        }

        // 2. 双击状态栏：取消单选定时器，立刻唤出词典主界面
        if event.clickCount == 2 {
            singleClickTimer?.invalidate()
            singleClickTimer = nil
            openMainWindowAction()
            return
        }

        // 3. 单击状态栏：延时 0.22s 判定是否为双击，若超时未双击则弹出菜单
        if event.clickCount == 1 {
            singleClickTimer?.invalidate()
            singleClickTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.popUpStatusMenu()
                }
            }
        }
    }

    /// 弹出状态栏功能菜单
    public func popUpStatusMenu() {
        guard let button = statusItem?.button else { return }
        let menu = buildMenu()
        button.isHighlighted = true
        statusItem?.popUpMenu(menu)
        button.isHighlighted = false
    }

    public func updateMenu() {
        // 保留接口以兼容现有触发刷新
    }

    public func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // 标题
        let titleItem = NSMenuItem(title: "MacDict 词典", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        // 打开词典主界面
        let mainItem = NSMenuItem(
            title: "打开词典主界面...",
            action: #selector(openMainWindowAction),
            keyEquivalent: "m"
        )
        mainItem.target = self
        menu.addItem(mainItem)
        menu.addItem(NSMenuItem.separator())

        // 悬停取词开关
        let hoverItem = NSMenuItem(
            title: "悬停取词",
            action: #selector(toggleHoverAction),
            keyEquivalent: "h"
        )
        hoverItem.keyEquivalentModifierMask = [.option, .command]
        hoverItem.target = self
        hoverItem.state = SettingsStore.shared.isHoverLookupEnabled ? .on : .off
        menu.addItem(hoverItem)

        // 快捷键查词开关
        let shortcutItem = NSMenuItem(
            title: "快捷键查词 (⌥D)",
            action: #selector(toggleShortcutAction),
            keyEquivalent: "s"
        )
        shortcutItem.keyEquivalentModifierMask = [.option, .command]
        shortcutItem.target = self
        shortcutItem.state = SettingsStore.shared.isShortcutLookupEnabled ? .on : .off
        menu.addItem(shortcutItem)

        // AI 智能问答对话 (⌥⌘A)
        let aiChatItem = NSMenuItem(
            title: "AI 智能问答对话...",
            action: #selector(openAIChatAction),
            keyEquivalent: "a"
        )
        aiChatItem.keyEquivalentModifierMask = [.option, .command]
        aiChatItem.target = self
        menu.addItem(aiChatItem)

        menu.addItem(NSMenuItem.separator())

        // 生词本
        let vocabItem = NSMenuItem(title: "生词本...", action: #selector(openVocabAction), keyEquivalent: "b")
        vocabItem.target = self
        menu.addItem(vocabItem)

        // 偏好设置
        let settingsItem = NSMenuItem(title: "偏好设置...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 辅助功能授权状态
        let isTrusted = AXIsProcessTrusted()
        let authItem = NSMenuItem(
            title: isTrusted ? "✓ 辅助功能权限已授权" : "⚠️ 需开启辅助功能权限",
            action: #selector(requestAccessibilityAction),
            keyEquivalent: ""
        )
        authItem.target = self
        menu.addItem(authItem)

        menu.addItem(NSMenuItem.separator())

        // 退出
        let quitItem = NSMenuItem(title: "退出 MacDict", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func toggleHoverAction() {
        ToggleManager.shared.toggleHoverLookup()
    }

    @objc private func toggleShortcutAction() {
        ToggleManager.shared.toggleShortcutLookup()
    }

    @objc public func openMainWindowAction() {
        MainWindowController.shared.showWindow()
    }

    @objc public func openAIChatAction() {
        AIChatWindowController.shared.show(
            word: DictionaryEngine.shared.currentWord,
            context: DictionaryEngine.shared.contextSentence
        )
    }

    @objc public func openVocabAction() {
        if vocabWindow == nil || vocabWindow?.isVisible == false {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "生词本 - MacDict"
            window.center()
            window.contentView = NSHostingView(rootView: VocabularyWindowView())
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.vocabWindow = window
        }
        vocabWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc public func openSettingsAction() {
        aLog("打开偏好设置窗口 — current settingsWindow: \(settingsWindow == nil ? "nil(新建)" : "已存在")")
        if settingsWindow == nil || settingsWindow?.isVisible == false {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "偏好设置 - MacDict"
            window.center()
            window.contentView = NSHostingView(rootView: SettingsWindowView())
            window.isReleasedWhenClosed = false   // ← 关键：防止关闭时自动释放再被访问
            window.delegate = self                 // ← 监听关闭事件
            self.settingsWindow = window
            aLog("创建新设置窗口")
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func requestAccessibilityAction() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}

// MARK: - NSWindowDelegate（防止窗口关闭后复用已释放对象崩溃）
extension StatusMenuController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if w === settingsWindow {
            aLog("设置窗口已关闭，清除引用")
            settingsWindow = nil
        } else if w === vocabWindow {
            aLog("生词本窗口已关闭，清除引用")
            vocabWindow = nil
        }
    }
}
