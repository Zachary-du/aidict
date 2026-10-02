import AppKit
import SwiftUI

public enum TriggerSource: Sendable {
    case hover
    case manual
}

@MainActor
public final class HUDPanel: NSPanel {
    public static let shared = HUDPanel()

    public private(set) var currentTriggerSource: TriggerSource = .manual
    public var isResizing: Bool = false
    public var onEscPressed: (() -> Bool)?
    /// 是否正处于 AI 问答对话交互模式。处于 AI 对话时，锁定窗口不因鼠标移开或点击外部关闭
    public var isInAIChat: Bool = false

    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    private init() {
        let initialW = CGFloat(SettingsStore.shared.hudWidth)
        let initialH = CGFloat(SettingsStore.shared.hudHeight)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: initialW, height: initialH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true

        let rootView = HUDView(onClose: { [weak self] in
            self?.dismiss()
        })
        self.contentView = NSHostingView(rootView: rootView)
    }

    /// 实时调整面板尺寸并保持左上角不动
    public func updateSize(width: CGFloat, height: CGFloat) {
        let clampedW = max(380, min(850, width))
        let clampedH = max(320, min(950, height))
        let oldFrame = self.frame
        let newOriginY = oldFrame.origin.y - (clampedH - oldFrame.size.height)
        self.setFrame(NSRect(x: oldFrame.origin.x, y: newOriginY, width: clampedW, height: clampedH), display: true)
        if HUDCompanionPanel.shared.isVisible {
            HUDCompanionPanel.shared.updatePosition(relativeTo: self.frame)
        }
    }

    /// 当用户点击编辑文本框时，激活应用并使面板获得键盘焦点与输入法支持
    public func activateForEditing() {
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
    }

    public func show(at screenPoint: NSPoint, source: TriggerSource = .manual) {
        self.isInAIChat = false
        self.currentTriggerSource = source
        guard let screen = NSScreen.screens.first(where: { NSPointInRect(screenPoint, $0.frame) }) ?? NSScreen.main else {
            return
        }

        let panelWidth = CGFloat(SettingsStore.shared.hudWidth)
        let panelHeight = CGFloat(SettingsStore.shared.hudHeight)

        // 智能定位：默认出现在光标右下方偏移 12 像素
        var x = screenPoint.x + 12
        var y = screenPoint.y - panelHeight - 12

        // 右侧边缘防溢出
        if x + panelWidth > screen.visibleFrame.maxX - 10 {
            x = screenPoint.x - panelWidth - 12
        }

        // 底部边缘防溢出
        if y < screen.visibleFrame.minY + 10 {
            y = screenPoint.y + 12
        }

        self.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        self.alphaValue = 0
        self.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1.0
        }

        setupDismissMonitors()
    }

    public func dismiss() {
        self.isInAIChat = false
        HUDCompanionPanel.shared.dismiss()
        removeDismissMonitors()
        HoverMonitor.shared.notifyDismissed(at: NSEvent.mouseLocation, word: DictionaryEngine.shared.currentWord)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.orderOut(nil)
            }
        })
    }

    private func setupDismissMonitors() {
        removeDismissMonitors()

        // 本地键盘监听 Esc
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // 53 是 Esc
                if let handled = self?.onEscPressed?(), handled {
                    return nil
                }
                self?.dismiss()
                return nil
            }
            return event
        }

        // 全局事件监听：捕获在其他应用中按下的 Esc 键，以及窗口外部点击
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.isVisible else { return }

            if event.type == .keyDown && event.keyCode == 53 {
                if let handled = self.onEscPressed?(), handled {
                    return
                }
                self.dismiss()
                return
            }

            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                let clickLocation = NSEvent.mouseLocation
                let inMain = self.frame.contains(clickLocation)
                let inCompanion = HUDCompanionPanel.shared.isVisible && HUDCompanionPanel.shared.frame.contains(clickLocation)
                if !inMain && !inCompanion {
                    // 如果正处于 AI 对话中，严禁因点击外部关闭窗口，必须由用户显式点击关闭按钮
                    if self.isInAIChat {
                        return
                    }
                    self.dismiss()
                }
            }
        }
    }

    private func removeDismissMonitors() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }
}
