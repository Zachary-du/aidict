import AppKit
import Foundation
import SwiftUI

/// 自动检查更新与版本管理服务
@MainActor
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    /// 当前应用版本号
    public static let currentVersion = "1.1.0"
    public static let buildNumber = "110"
    public static let repoURL = "https://github.com/Zachary-du/aidict"
    public static let apiLatestReleaseURL = "https://api.github.com/repos/Zachary-du/aidict/releases/latest"

    @Published public var isChecking: Bool = false
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var hasNewVersion: Bool = false
    @Published public var latestVersion: String = ""
    @Published public var releaseTitle: String = ""
    @Published public var releaseNotes: String = ""
    @Published public var downloadURL: URL? = nil
    @Published public var releasePageURL: URL? = nil
    @Published public var statusMessage: String = "当前已是最新版本 (v\(currentVersion))"
    @Published public var lastCheckTime: Date? = nil

    private init() {
        if SettingsStore.shared.autoCheckUpdates {
            Task {
                // 启动 3 秒后静默检查一次
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await checkForUpdates(silent: true)
            }
        }
    }

    /// 检查是否有新版本
    /// - Parameter silent: 是否静默检查（启动时为静默，用户手动点击时显示状态提示）
    public func checkForUpdates(silent: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        if !silent {
            statusMessage = "正在连接 GitHub 检查最新版本..."
        }

        defer {
            isChecking = false
            lastCheckTime = Date()
        }

        guard let url = URL(string: Self.apiLatestReleaseURL) else {
            statusMessage = "无效的更新地址"
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("MacDict/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                if !silent { statusMessage = "网络响应异常" }
                return
            }

            if httpResponse.statusCode == 404 {
                // 尚未发布 release 时，保持当前版本
                if !silent {
                    statusMessage = "当前已是最新版本 (v\(Self.currentVersion))"
                }
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if !silent { statusMessage = "检查更新失败 (HTTP \(httpResponse.statusCode))" }
                return
            }

            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
            }
            struct ReleaseInfo: Decodable {
                let tag_name: String
                let name: String?
                let body: String?
                let html_url: String
                let assets: [Asset]
            }

            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            let rawTag = release.tag_name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanRemoteVersion = rawTag.hasPrefix("v") || rawTag.hasPrefix("V") ? String(rawTag.dropFirst()) : rawTag

            self.latestVersion = cleanRemoteVersion
            self.releaseTitle = release.name ?? "MacDict v\(cleanRemoteVersion)"
            self.releaseNotes = release.body ?? ""
            self.releasePageURL = URL(string: release.html_url)

            // 寻找 DMG 安装包下载链接
            if let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) {
                self.downloadURL = URL(string: dmgAsset.browser_download_url)
            } else {
                self.downloadURL = URL(string: release.html_url)
            }

            // 版本比较
            if isVersionNewer(remote: cleanRemoteVersion, current: Self.currentVersion) {
                self.hasNewVersion = true
                self.statusMessage = "发现新版本: v\(cleanRemoteVersion)"
            } else {
                self.hasNewVersion = false
                self.statusMessage = "当前已是最新版本 (v\(Self.currentVersion))"
            }
        } catch {
            if !silent {
                self.statusMessage = "检查更新失败: \(error.localizedDescription)"
            }
        }
    }

    /// 一键下载 DMG 并自动打开挂载
    public func downloadLatestDMG() {
        guard let url = downloadURL else {
            if let page = releasePageURL {
                NSWorkspace.shared.open(page)
            }
            return
        }

        if !url.absoluteString.hasSuffix(".dmg") {
            // 没有直接 dmg 资源则直接跳转至发布页
            NSWorkspace.shared.open(url)
            return
        }

        isDownloading = true
        statusMessage = "正在下载最新安装包..."

        Task.detached {
            do {
                let (tempURL, _) = try await URLSession.shared.download(from: url)
                let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let destURL = downloadsDir.appendingPathComponent("MacDict-Installer.dmg")

                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: tempURL, to: destURL)

                await MainActor.run {
                    self.isDownloading = false
                    self.statusMessage = "下载完成！已保存至 Downloads 目录"
                    // 自动打开并挂载 DMG
                    NSWorkspace.shared.open(destURL)
                }
            } catch {
                await MainActor.run {
                    self.isDownloading = false
                    self.statusMessage = "下载失败: \(error.localizedDescription)"
                    if let page = self.releasePageURL {
                        NSWorkspace.shared.open(page)
                    }
                }
            }
        }
    }

    /// 版本比较逻辑 (支持 "1.1.0" > "1.0.0")
    private func isVersionNewer(remote: String, current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(remoteParts.count, currentParts.count)
        for i in 0..<maxCount {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}
