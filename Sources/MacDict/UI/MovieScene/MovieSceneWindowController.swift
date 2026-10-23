import AppKit
import SwiftUI

@MainActor
public final class MovieSceneWindowController: NSObject, NSWindowDelegate {
    public static let shared = MovieSceneWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    /// 显示或激活影视原声名场面独立弹窗
    /// - Parameters:
    ///   - word: 待检索的英文单词或短语
    ///   - relativeTo: 可选的父窗口或 HUD 面板坐标，用于智能吸附定位
    public func show(word: String? = nil, relativeTo: NSRect? = nil) {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "影视原声名场面"
            win.titlebarAppearsTransparent = true
            win.toolbarStyle = .unifiedCompact
            win.minSize = NSSize(width: 420, height: 420)
            win.level = .floating
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.setFrameAutosaveName("MacDictMovieSceneWindow")
            win.contentView = NSHostingView(rootView: MovieSceneView())
            win.isReleasedWhenClosed = false
            win.delegate = self
            self.window = win

            // 初次定位：优先智能停靠在 HUD 或主窗口右侧，否则屏幕居中
            positionWindow(win, relativeTo: relativeTo)
        } else if let win = window, !win.isVisible {
            positionWindow(win, relativeTo: relativeTo)
        }

        if let w = word?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty {
            MovieSceneService.shared.fetchScenes(for: w)
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 若窗口当前正处于打开可见状态，随新词条自动刷新；若窗口关闭则绝不自启
    public func updateWordIfVisible(word: String) {
        guard let win = window, win.isVisible else { return }
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        MovieSceneService.shared.fetchScenes(for: clean)
    }

    public func toggle(word: String? = nil, relativeTo: NSRect? = nil) {
        if let win = window, win.isVisible {
            win.orderOut(nil)
        } else {
            show(word: word, relativeTo: relativeTo)
        }
    }

    private func positionWindow(_ win: NSWindow, relativeTo parentFrame: NSRect?) {
        guard let pFrame = parentFrame, let screen = NSScreen.main else {
            win.center()
            return
        }

        let spacing: CGFloat = 12
        var x = pFrame.maxX + spacing
        var y = pFrame.maxY - win.frame.height

        // 若右侧超出屏幕可视边界，则改停靠在左侧
        if x + win.frame.width > screen.visibleFrame.maxX {
            x = pFrame.minX - spacing - win.frame.width
        }

        // 上下边界防护
        if y < screen.visibleFrame.minY {
            y = screen.visibleFrame.minY + 20
        }
        if y + win.frame.height > screen.visibleFrame.maxY {
            y = screen.visibleFrame.maxY - win.frame.height - 20
        }

        win.setFrameOrigin(NSPoint(x: max(screen.visibleFrame.minX + 10, x), y: y))
    }

    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        // 关闭时若正在朗读，停止语音
        AudioPlayer.shared.stop()
    }
}
