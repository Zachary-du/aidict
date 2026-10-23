import Foundation
import Combine

@MainActor
public final class MovieSceneService: ObservableObject {
    public static let shared = MovieSceneService()

    @Published public var currentWord: String = ""
    @Published public var scenes: [MovieSceneItem] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var playbackSpeed: Float = 1.0  // 1.0x 正常 / 0.85x 慢速慢读

    private let memoryCache = NSCache<NSString, NSArray>()
    private var activeTask: Task<Void, Never>?

    private var cacheDir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MacDict/MovieScenes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {}

    /// 获取某词条的影视原声名场面（优先内存与磁盘缓存，次选 AI 剧作检索）
    public func fetchScenes(for rawWord: String, forceRefresh: Bool = false) {
        let clean = rawWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else {
            self.currentWord = ""
            self.scenes = []
            self.isLoading = false
            self.errorMessage = nil
            return
        }

        self.currentWord = clean

        // 1. 内存缓存命中
        if !forceRefresh, let cached = memoryCache.object(forKey: clean as NSString) as? [MovieSceneItem], !cached.isEmpty {
            self.scenes = cached
            self.isLoading = false
            self.errorMessage = nil
            return
        }

        // 2. 本地磁盘缓存命中
        if !forceRefresh, let diskItems = loadFromDisk(word: clean), !diskItems.isEmpty {
            memoryCache.setObject(diskItems as NSArray, forKey: clean as NSString)
            self.scenes = diskItems
            self.isLoading = false
            self.errorMessage = nil
            return
        }

        // 3. 异步并发拉取
        self.scenes = []
        self.isLoading = true
        self.errorMessage = nil

        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let items = try await self.queryAIForMovieScenes(word: clean)
                guard !Task.isCancelled, self.currentWord == clean else { return }

                self.scenes = items
                self.isLoading = false
                self.errorMessage = items.isEmpty ? "暂未检索到该词的影视原声台词" : nil

                if !items.isEmpty {
                    self.memoryCache.setObject(items as NSArray, forKey: clean as NSString)
                    self.saveToDisk(word: clean, items: items)
                }
            } catch {
                guard !Task.isCancelled, self.currentWord == clean else { return }
                self.isLoading = false
                self.errorMessage = error.localizedDescription

                // 如果网络异常或无 Key，提供兜底生成
                let fallback = self.generateFallbackScenes(word: clean)
                if !fallback.isEmpty {
                    self.scenes = fallback
                    self.errorMessage = nil
                }
            }
        }
    }

    // MARK: - AI 影视剧台词高光检索
    private func queryAIForMovieScenes(word: String) async throws -> [MovieSceneItem] {
        let s = SettingsStore.shared
        let endpoint = s.aiEndpoint.isEmpty
            ? "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
            : s.aiEndpoint
        let apiKey = s.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = s.aiModel.isEmpty ? "gemini-2.0-flash" : s.aiModel

        guard !apiKey.isEmpty else {
            throw NSError(domain: "MovieScene", code: 401, userInfo: [NSLocalizedDescriptionKey: "未配置 AI API Key，请在设置中填写"])
        }

        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "MovieScene", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 AI 接口地址"])
        }

        let prompt = """
请为英文词汇或短语「\(word)」从欧美知名经典影视剧（如《绝命毒师》《老友记》《生活大爆炸》《摩登家庭》《神探夏洛克》《钢铁侠》《权力的游戏》《纸牌屋》《华尔街之狼》《无耻之徒》《穿普拉达的女王》等）中检索 3~4 个真实包含该单词的经典名场面台词。

必须严格返回 JSON 数组（不要包裹任何解释性文字或多余文本）：
[
  {
    "title": "影视剧中英文名（如：Breaking Bad / 绝命毒师）",
    "seasonEpisode": "季集数或年份（如：S04E04 或 2008）",
    "character": "角色姓名（如：Walter White）",
    "quote": "真实英文原声台词（务必完整自然，且必须包含目标词汇）",
    "translation": "精准中文对照翻译",
    "context": "该场面的剧情背景简析（20~35字）"
  }
]
"""

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "你是一位精通欧美电影、美剧与影视台词的电影学者。你熟悉海量经典欧美影视剧剧本与真实台词。请严格以 JSON 格式输出真实、地道的台词名场面。"],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "max_tokens": 800
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: cfg)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errStr = String(data: data, encoding: .utf8) ?? "HTTP 错误"
            throw NSError(domain: "MovieScene", code: 500, userInfo: [NSLocalizedDescriptionKey: "影视台词检索失败: \(errStr)"])
        }

        struct ChatChoice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        struct ChatCompletion: Decodable { let choices: [ChatChoice] }

        let decoded = try JSONDecoder().decode(ChatCompletion.self, from: data)
        guard let rawContent = decoded.choices.first?.message.content else {
            throw NSError(domain: "MovieScene", code: -2, userInfo: [NSLocalizedDescriptionKey: "AI 返回结果为空"])
        }

        return parseMovieScenesJSON(from: rawContent)
    }

    private func parseMovieScenesJSON(from rawText: String) -> [MovieSceneItem] {
        var clean = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```json") {
            clean = String(clean.dropFirst(7))
        } else if clean.hasPrefix("```") {
            clean = String(clean.dropFirst(3))
        }
        if clean.hasSuffix("```") {
            clean = String(clean.dropLast(3))
        }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = clean.data(using: .utf8) else { return [] }

        struct RawItem: Decodable {
            let title: String?
            let seasonEpisode: String?
            let character: String?
            let quote: String?
            let translation: String?
            let context: String?
        }

        guard let rawItems = try? JSONDecoder().decode([RawItem].self, from: data) else {
            return []
        }

        return rawItems.compactMap { r in
            guard let q = r.quote, !q.isEmpty, let tr = r.translation, !tr.isEmpty else { return nil }
            return MovieSceneItem(
                title: r.title ?? "经典欧美影视",
                seasonEpisode: r.seasonEpisode,
                character: r.character,
                quote: q,
                translation: tr,
                context: r.context
            )
        }
    }

    // MARK: - 智能兜底示例生成
    private func generateFallbackScenes(word: String) -> [MovieSceneItem] {
        return [
            MovieSceneItem(
                title: "Friends / 老友记",
                seasonEpisode: "S05E09",
                character: "Ross Geller",
                quote: "Someone at work ate my sandwich! It had a moist maker!",
                translation: "有人在单位把我的三明治吃了！那里面可是放了浸汁肉汁层面包的！",
                context: "罗斯向大家愤怒控诉自己在博物馆被同事偷吃三明治的崩溃时刻"
            )
        ]
    }

    // MARK: - 本地缓存管理
    private func fileURL(for word: String) -> URL {
        let safeName = word.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? word
        return cacheDir.appendingPathComponent("\(safeName).json")
    }

    private func saveToDisk(word: String, items: [MovieSceneItem]) {
        let url = fileURL(for: word)
        Task.detached(priority: .background) {
            if let data = try? JSONEncoder().encode(items) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func loadFromDisk(word: String) -> [MovieSceneItem]? {
        let url = fileURL(for: word)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([MovieSceneItem].self, from: data) else {
            return nil
        }
        return items
    }
}
