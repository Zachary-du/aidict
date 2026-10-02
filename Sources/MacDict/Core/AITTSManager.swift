import Foundation
import CryptoKit

public final class AITTSManager: @unchecked Sendable {
    public static let shared = AITTSManager()

    private let cacheDirectory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = caches.appendingPathComponent("com.dylan.MacDict/audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// 获取高保真音频文件 URL（优先读缓存，无缓存则 AI 神经合成 / 原声流并写入磁盘）
    /// - Parameters:
    ///   - text: 待发音文本 (单词、短语或句子)
    ///   - accent: "us" 或 "uk"
    ///   - engineOverride: 可选强制覆盖语音引擎 ("neural", "openai", "studio")
    public func resolveAudioURL(text: String, accent: String = "us", engineOverride: String? = nil) async -> URL? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return nil }

        let engine = engineOverride ?? SettingsStore.shared.ttsEngine
        let voice = SettingsStore.shared.openaiTTSVoice
        let cacheKey = "\(engine)_\(accent)_\(voice)_\(cleanText.lowercased())"
        let hash = Insecure.MD5.hash(data: Data(cacheKey.utf8)).map { String(format: "%02hhx", $0) }.joined()
        let cachedFile = cacheDirectory.appendingPathComponent("\(hash).mp3")

        // 1. 本地缓存命中 (0 毫秒即时响应)
        if FileManager.default.fileExists(atPath: cachedFile.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: cachedFile.path),
           let size = attrs[.size] as? Int64, size > 256 {
            return cachedFile
        }

        // 2. 根据选定引擎进行在线合成
        do {
            let audioData: Data
            if engine == "openai" {
                audioData = try await fetchOpenAITTS(text: cleanText, voice: voice)
            } else {
                // "neural" 模式：若为单单词或极短短语，优先尝试 Studio 原声真人库，若无或为长句则使用 Google Neural
                let isShortWord = !cleanText.contains(" ") && cleanText.count < 35
                if isShortWord, let studioData = try? await fetchStudioHumanAudio(text: cleanText, accent: accent) {
                    audioData = studioData
                } else {
                    audioData = try await fetchGoogleNeuralTTS(text: cleanText, accent: accent)
                }
            }

            try audioData.write(to: cachedFile, options: .atomic)
            return cachedFile
        } catch {
            // 在线合成失败时，尝试 Studio 真人库回退
            if let fallbackData = try? await fetchStudioHumanAudio(text: cleanText, accent: accent) {
                try? fallbackData.write(to: cachedFile, options: .atomic)
                return cachedFile
            }
            return nil
        }
    }

    // MARK: - 引擎实现: Google Neural 高拟真神经语音
    private func fetchGoogleNeuralTTS(text: String, accent: String) async throws -> Data {
        let lang = accent == "uk" ? "en-GB" : "en-US"
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/translate_tts?ie=UTF-8&tl=\(lang)&client=tw-ob&q=\(encoded)") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 7.0
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue("https://translate.google.com/", forHTTPHeaderField: "Referer")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 256 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - 引擎实现: OpenAI / 兼容端点 Neural TTS
    private func fetchOpenAITTS(text: String, voice: String) async throws -> Data {
        let settings = SettingsStore.shared
        let endpointStr = settings.openaiTTSEndpoint.isEmpty
            ? "https://api.openai.com/v1/audio/speech"
            : settings.openaiTTSEndpoint

        guard let url = URL(string: endpointStr) else {
            throw URLError(.badURL)
        }

        let apiKey = settings.aiApiKey
        guard !apiKey.isEmpty else {
            throw NSError(domain: "AITTS", code: 401, userInfo: [NSLocalizedDescriptionKey: "请在设置中配置 AI API Key"])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": "tts-1",
            "input": text,
            "voice": voice
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count > 256 else {
            let errDetail = String(data: data, encoding: .utf8) ?? "HTTP \( (resp as? HTTPURLResponse)?.statusCode ?? -1)"
            throw NSError(domain: "AITTS", code: 500, userInfo: [NSLocalizedDescriptionKey: "OpenAI TTS 失败: \(errDetail)"])
        }
        return data
    }

    // MARK: - 引擎实现: 专业录音室真人原声 (Studio Human Audio CDN)
    public func fetchStudioHumanAudio(text: String, accent: String) async throws -> Data {
        let typeParam = accent == "uk" ? "1" : "2"
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://dict.youdao.com/dictvoice?audio=\(encoded)&type=\(typeParam)") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 5.0
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200, data.count > 256 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// 清空音频缓存
    public func clearAudioCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// 获取缓存大小（字节）
    public var cacheSizeInBytes: Int64 {
        guard let enumerator = FileManager.default.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let val = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = val.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
