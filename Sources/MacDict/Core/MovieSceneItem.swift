import Foundation

/// 影视原声台词名场面数据结构
public struct MovieSceneItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String           // 影视剧名，如 "The Office (2005) - S08E09" 或 "Breaking Bad / 绝命毒师"
    public let seasonEpisode: String?  // 季集或年份，如 "S08E09" 或 "2008"
    public let character: String?      // 角色名
    public let quote: String           // 英文原声台词
    public let translation: String     // 中文翻译
    public let context: String?        // 语境或片段时长 (如 "1.5s")
    public let videoURL: String?       // 真实原声视频/音频切片直链 (如 https://y.yarn.co/...mp4)
    public let posterURL: String?      // 真实剧照缩略图直链
    public let isRealSoundtrack: Bool  // 是否为 100% 电影美剧截取的真实录音原声 (非 AI TTS)

    public init(
        id: String = UUID().uuidString,
        title: String,
        seasonEpisode: String? = nil,
        character: String? = nil,
        quote: String,
        translation: String,
        context: String? = nil,
        videoURL: String? = nil,
        posterURL: String? = nil,
        isRealSoundtrack: Bool = false
    ) {
        self.id = id
        self.title = title
        self.seasonEpisode = seasonEpisode
        self.character = character
        self.quote = quote
        self.translation = translation
        self.context = context
        self.videoURL = videoURL
        self.posterURL = posterURL
        self.isRealSoundtrack = isRealSoundtrack
    }
}
