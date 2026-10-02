import Foundation
import AppKit
import Combine
import SwiftUI

public final class ToggleManager: ObservableObject, @unchecked Sendable {
    public static let shared = ToggleManager()

    private var toastWindow: NSPanel?
    private var dismissTimer: Timer?

    private init() {}

    public func toggleHoverLookup() {
        SettingsStore.shared.isHoverLookupEnabled.toggle()
        let state = SettingsStore.shared.isHoverLookupEnabled
        showNotification(title: "悬停取词", message: state ? "已开启" : "已关闭", icon: state ? "cursorarrow.rays" : "cursorarrow.slash")
    }

    public func toggleShortcutLookup() {
        SettingsStore.shared.isShortcutLookupEnabled.toggle()
        let state = SettingsStore.shared.isShortcutLookupEnabled
        showNotification(title: "划词快捷键", message: state ? "已开启" : "已关闭", icon: state ? "keyboard" : "keyboard.badge.ellipsis")
    }

    public func showNotification(title: String, message: String, icon: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.dismissTimer?.invalidate()

            if self.toastWindow == nil {
                let panel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 220, height: 75),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.level = .floating
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = true
                self.toastWindow = panel
            }

            let view = NSHostingView(rootView: ToastView(title: title, message: message, icon: icon))
            self.toastWindow?.contentView = view

            if let screen = NSScreen.main {
                let x = screen.frame.midX - 110
                let y = screen.frame.maxY - 140
                self.toastWindow?.setFrameOrigin(NSPoint(x: x, y: y))
            }

            self.toastWindow?.alphaValue = 0
            self.toastWindow?.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.toastWindow?.animator().alphaValue = 1.0
            }

            self.dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.3
                        self.toastWindow?.animator().alphaValue = 0.0
                    }, completionHandler: {
                        MainActor.assumeIsolated {
                            self.toastWindow?.orderOut(nil)
                        }
                    })
                }
            }
        }
    }
}

private struct ToastView: View {
    let title: String
    let message: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}
