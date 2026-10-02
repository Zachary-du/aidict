import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 初始化日志系统 & 崩溃捕获
        AppLogger.shared.logCrashHandler()
        aLog("App 启动")

        // 设置为后台常驻工具形态 (不在 Dock 栏显现，常驻右上角菜单栏)
        NSApp.setActivationPolicy(.accessory)

        // 检查并提示辅助功能授权
        Permissions.ensureAccessibility()

        // 初始化菜单栏状态项
        StatusMenuController.shared.setupStatusItem()

        // 启动后台监听器
        HoverMonitor.shared.start()
        SelectionMonitor.shared.start()

        aLog("App 启动完成 — 日志文件: \(AppLogger.shared.logFileURL.path)")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HoverMonitor.shared.stop()
    }
}
