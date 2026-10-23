import Foundation

/// 影视原声台词名场面数据结构
public struct MovieSceneItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String           // 影视剧名，如 "Breaking Bad / 绝命毒师"
    public let seasonEpisode: String?  // 季集或年份，如 "S04E04" 或 "2008"
    public let character: String?      // 角色名，如 "Hank Schrader"
    public let quote: String           // 真实英文台词
    public let translation: String     // 中文翻译
    public let context: String?        // 剧情语境解读

    public init(
        id: String = UUID().uuidString,
        title: String,
        seasonEpisode: String? = nil,
        character: String? = nil,
        quote: String,
        translation: String,
        context: String? = nil
    ) {
        self.id = id
        self.title = title
        self.seasonEpisode = seasonEpisode
        self.character = character
        self.quote = quote
        self.translation = translation
        self.context = context
    }
}
