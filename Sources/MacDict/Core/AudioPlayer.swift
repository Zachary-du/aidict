import Foundation
import AVFoundation

public final class AudioPlayer: NSObject, @unchecked Sendable {
    public static let shared = AudioPlayer()

    private let synthesizer = AVSpeechSynthesizer()
    private var networkPlayer: AVPlayer?
    private var currentAudioTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    /// 朗读单词或文本，优先使用真实词典原声，次选 AI 神经高保真语音，最后回退到系统本地 TTS
    /// - Parameters:
    ///   - text:        待发音文本 (单词、短语或整句)
    ///   - audioURL:    美式原声 URL
    ///   - audioURL_uk: 英式原声 URL
    ///   - accent:      "us" 或 "uk"
    public func speak(text: String,
                      audioURL: String? = nil,
                      audioURL_uk: String? = nil,
                      accent: String = "us") {
        stop()

        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        // 1. 根据口音偏好选择词典原始音频，并严格防御例句音频泄露
        let candidateURL: String? = (accent == "uk") ? (audioURL_uk ?? audioURL) : (audioURL ?? audioURL_uk)
        if let urlStr = candidateURL, !urlStr.isEmpty,
           !urlStr.contains("exaProns"), !urlStr.contains("exa_sounds"),
           let url = URL(string: urlStr) {
            playAudioURL(url)
            return
        }

        // 2. 无词典词头原声时，检查用户是否强制系统原生 TTS
        let engine = SettingsStore.shared.ttsEngine
        if engine == "system" {
            synthesizeLocal(text: cleanText, accent: accent)
            return
        }

        // 3. 启用 AI 神经语音 (Neural TTS / Studio CDN 流式回退与本地磁盘缓存)
        currentAudioTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let localFileURL = await AITTSManager.shared.resolveAudioURL(text: cleanText, accent: accent) {
                // 确保在主线程播放
                self.playAudioURL(localFileURL)
            } else {
                // 网络异常或离线，优雅回退到系统本地语音
                self.synthesizeLocal(text: cleanText, accent: accent)
            }
        }
    }

    /// 播放例句音频（优先真实录音棚 MP3 直链，若无或失败则走高保真 AI 神经语音）
    public func playSentence(text: String, audioURL: String? = nil, accent: String? = nil) {
        stop()

        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        // 1. 如果有词典原厂真人录音直链，直接播放
        if let urlStr = audioURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
            playAudioURL(url)
            return
        }

        // 2. 否则通过 AI 神经高保真语音（Google Neural / OpenAI / macOS Enhanced）朗读
        let prefAccent = accent ?? SettingsStore.shared.preferredAccent
        let engine = SettingsStore.shared.ttsEngine
        if engine == "system" {
            synthesizeLocal(text: cleanText, accent: prefAccent)
            return
        }

        currentAudioTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let localFileURL = await AITTSManager.shared.resolveAudioURL(text: cleanText, accent: prefAccent) {
                self.playAudioURL(localFileURL)
            } else {
                self.synthesizeLocal(text: cleanText, accent: prefAccent)
            }
        }
    }

    private func playAudioURL(_ url: URL) {
        networkPlayer = AVPlayer(playerItem: AVPlayerItem(url: url))
        networkPlayer?.play()
    }

    /// 系统本地 TTS 兜底播放（智能挑选 macOS 系统中最高质量声音）
    public func synthesizeLocal(text: String, accent: String) {
        let langCode = accent == "uk" ? "en-GB" : "en-US"
        let utterance = AVSpeechUtterance(string: text)

        let selectedVoice = pickBestLocalVoice(accent: accent, langCode: langCode)
        utterance.voice = selectedVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.88
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.95
        synthesizer.speak(utterance)
    }

    /// 智能挑选本地系统中音质最佳的语音（优先 Premium/Enhanced/Siri，避免刺耳机械音）
    private func pickBestLocalVoice(accent: String, langCode: String) -> AVSpeechSynthesisVoice? {
        let allVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().starts(with: langCode.lowercased())
        }

        // 1. 首选 Premium 顶配神经语音
        if let premium = allVoices.first(where: { $0.quality == .premium }) {
            return premium
        }
        // 2. 次选 Enhanced 高清语音
        if let enhanced = allVoices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        // 3. 尝试 Siri / 经典高质量名模语音
        let preferredNames = accent == "uk"
            ? ["Stephanie", "Daniel", "Oliver", "Martha", "Siri"]
            : ["Ava", "Samantha", "Evan", "Nathan", "Zoe", "Allison", "Siri"]

        for name in preferredNames {
            if let v = allVoices.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
                return v
            }
        }

        // 4. 默认语言回退
        return AVSpeechSynthesisVoice(language: langCode)
    }

    public func stop() {
        currentAudioTask?.cancel()
        currentAudioTask = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        networkPlayer?.pause()
        networkPlayer = nil
    }

    /// 列出所有可用的英语声音
    public static func listEnglishVoices() -> [(id: String, name: String, lang: String)] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map { (id: $0.identifier, name: $0.name, lang: $0.language) }
    }
}
