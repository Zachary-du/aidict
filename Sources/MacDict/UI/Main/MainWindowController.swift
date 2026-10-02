import AppKit
import SwiftUI

@MainActor
public final class MainWindowController: NSObject, NSWindowDelegate {
    public static let shared = MainWindowController()
    private var window: NSWindow?

    private override init() {
        super.init()
    }

    public func showWindow(word: String? = nil) {
        if window == nil || window?.isVisible == false {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "MacDict 词典"
            win.titlebarAppearsTransparent = true
            win.toolbarStyle = .unifiedCompact
            win.minSize = NSSize(width: 780, height: 500)
            win.center()
            win.setFrameAutosaveName("MacDictMainWindow")
            win.contentView = NSHostingView(rootView: MainWindowView())
            win.isReleasedWhenClosed = false
            win.delegate = self
            self.window = win
        }

        if let w = word?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty {
            DictionaryEngine.shared.lookup(word: w, triggerSource: .manual)
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func toggleWindow() {
        if let win = window, win.isVisible {
            win.orderOut(nil)
        } else {
            showWindow()
        }
    }

    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
