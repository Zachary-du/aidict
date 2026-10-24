import Foundation
import Combine
import AVFoundation

@MainActor
public final class MovieSceneService: ObservableObject {
    public static let shared = MovieSceneService()

    @Published public var currentWord: String = ""
    @Published public var scenes: [MovieSceneItem] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var currentlyPlayingClipId: String? = nil
    @Published public var isDownloadingClip: Bool = false

    private let memoryCache = NSCache<NSString, NSArray>()
    private var activeTask: Task<Void, Never>?
    private var moviePlayer: AVPlayer?
    private var playerObserver: Any?

    private var cacheDir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MacDict/MovieScenes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var clipsDir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MacDict/MovieClips", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        playerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.currentlyPlayingClipId = nil
            }
        }
    }

    deinit {
        if let obs = playerObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - 主入口：检索影视原声名场面
    public func fetchScenes(for rawWord: String, forceRefresh: Bool = false) {
        let clean = rawWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else {
            self.currentWord = ""
            self.scenes = []
            self.isLoading = false
            self.errorMessage = nil
            stopAudio()
            return
        }

        self.currentWord = clean
        stopAudio()

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

            // 优先尝试从影视原片切片库拉取 100% 真实原声音频/台词
            var realClips = await self.fetchYarnClips(word: clean)

            if !realClips.isEmpty {
                // 如果 AI 配置有效，异步为英文台词生成中文对照翻译
                realClips = await self.translateClipsWithAI(clips: realClips)
            } else {
                // 若切片库暂未收录该生僻词，平滑回退至 AI 经典电影剧作台词库
                do {
                    realClips = try await self.queryAIForMovieScenes(word: clean)
                } catch {
                    realClips = self.generateFallbackScenes(word: clean)
                }
            }

            guard !Task.isCancelled, self.currentWord == clean else { return }

            self.scenes = realClips
            self.isLoading = false
            self.errorMessage = realClips.isEmpty ? "暂未检索到该词的影视原声台词" : nil

            if !realClips.isEmpty {
                self.memoryCache.setObject(realClips as NSArray, forKey: clean as NSString)
                self.saveToDisk(word: clean, items: realClips)
            }
        }
    }

    // MARK: - 句子质量与长句过滤
    /// 判断是否为合格的影视原声对话完整长句子（严格过滤单字呼喊、音效标签与无意义歌词）
    public static func isValidSentenceQuote(_ rawQuote: String) -> Bool {
        // 1. 去除音效括号如 [screaming], (laughter), 和歌词标签 # ... #
        var clean = rawQuote
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\([^\\)]*\\)", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "#[^#]*#", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clean.isEmpty else { return false }

        // 2. 提取词汇 tokens
        let words = clean.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        // 3. 必须至少有 5 个英文单词，绝不接受 1~4 个词的单字呼喊
        guard words.count >= 5 else { return false }

        // 4. 至少要有 4 个不重复单词，防止单字复读 (如 "Senior, senior, senior, senior")
        let uniqueWords = Set(words.map { $0.lowercased() })
        guard uniqueWords.count >= 4 else { return false }

        return true
    }

    /// 计算台词质量评分（词数越多、信息越丰富、语境越完整的分数越高）
    public static func sentenceQualityScore(_ rawQuote: String) -> Int {
        guard isValidSentenceQuote(rawQuote) else { return 0 }
        let clean = rawQuote
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\([^\\)]*\\)", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "#[^#]*#", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = clean.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words.count
    }

    // MARK: - 真实影视切片原声抓取 (100% 真实原音录音，长句对白严选)
    private func fetchYarnClips(word: String) async -> [MovieSceneItem] {
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), !encoded.isEmpty else {
            return []
        }

        // 并发检索前 4 页切片数据 (每页 20 条，共检索 80 条)，确保筛选出真正高质量的完整长句子
        let pages = [0, 1, 2, 3]
        var allCandidateItems: [MovieSceneItem] = []

        await withTaskGroup(of: [MovieSceneItem].self) { group in
            for page in pages {
                group.addTask {
                    return await self.fetchYarnPage(encodedWord: encoded, page: page)
                }
            }

            for await pageItems in group {
                allCandidateItems.append(contentsOf: pageItems)
            }
        }

        // 去重与优质长句子过滤
        var seenIds = Set<String>()
        var validClips: [MovieSceneItem] = []

        for item in allCandidateItems {
            guard !seenIds.contains(item.id) else { continue }
            seenIds.insert(item.id)

            // 严格过滤：必须是 5 个单词以上且词汇不重复的完整长句子
            if Self.isValidSentenceQuote(item.quote) {
                validClips.append(item)
            }
        }

        // 如果单词检索未能凑足 3 条优质长句，尝试补充常见短语或搭配检索 (例如 "a " + word, "the " + word)
        if validClips.count < 3 {
            let collocations = ["a \(word)", "the \(word)"]
            await withTaskGroup(of: [MovieSceneItem].self) { group in
                for phrase in collocations {
                    if let encPhrase = phrase.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        group.addTask {
                            return await self.fetchYarnPage(encodedWord: encPhrase, page: 0)
                        }
                    }
                }
                for await phraseItems in group {
                    for item in phraseItems {
                        guard !seenIds.contains(item.id) else { continue }
                        seenIds.insert(item.id)
                        if Self.isValidSentenceQuote(item.quote) {
                            validClips.append(item)
                        }
                    }
                }
            }
        }

        // 按句子单词丰富度与质量由高到低排序，优先呈现语境最丰富、最生动完整的名场面长台词
        validClips.sort {
            Self.sentenceQualityScore($0.quote) > Self.sentenceQualityScore($1.quote)
        }

        return Array(validClips.prefix(5))
    }

    private func fetchYarnPage(encodedWord: String, page: Int) async -> [MovieSceneItem] {
        let pageParam = page > 0 ? "&p=\(page)" : ""
        guard let url = URL(string: "https://yarn.co/yarn-find?text=\(encodedWord)\(pageParam)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 6

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                return []
            }

            let pattern = #"/yarn-clip/([a-f0-9\-]+).*?<div class="title[^"]*"[^>]*>(.*?)</div>.*?class="play-time[^"]*"[^>]*>(.*?)</div>.*?<div class="transcript[^"]*"[^>]*>(.*?)</div>"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
                return []
            }

            let nsHTML = html as NSString
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))

            var items: [MovieSceneItem] = []
            for m in matches {
                guard m.numberOfRanges >= 5 else { continue }
                let cid = nsHTML.substring(with: m.range(at: 1))
                let rawTitle = nsHTML.substring(with: m.range(at: 2))
                let rawTime = nsHTML.substring(with: m.range(at: 3))
                let rawText = nsHTML.substring(with: m.range(at: 4))

                let title = cleanHTMLTags(rawTitle)
                let time = cleanHTMLTags(rawTime)
                let quote = cleanHTMLTags(rawText)

                guard !title.isEmpty, !quote.isEmpty else { continue }

                items.append(MovieSceneItem(
                    id: cid,
                    title: title,
                    seasonEpisode: extractSeasonEpisode(from: title),
                    character: nil,
                    quote: quote,
                    translation: "", // 稍后由 AI 填充
                    context: time.isEmpty ? nil : "原声时长 \(time)",
                    videoURL: "https://y.yarn.co/\(cid).mp4",
                    posterURL: "https://y.yarn.co/\(cid)_screenshot.jpg",
                    isRealSoundtrack: true
                ))
            }
            return items
        } catch {
            return []
        }
    }

    private func extractSeasonEpisode(from title: String) -> String? {
        let pattern = #"(S\d+E\d+|\(\d{4}\))"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: title, options: [], range: NSRange(title.startIndex..., in: title)),
           let r = Range(match.range(at: 1), in: title) {
            return String(title[r]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
        }
        return nil
    }

    private func cleanHTMLTags(_ str: String) -> String {
        var s = str.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "&#39;", with: "'")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 真实台词的中文翻译
    private func translateClipsWithAI(clips: [MovieSceneItem]) async -> [MovieSceneItem] {
        let s = SettingsStore.shared
        let apiKey = s.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return clips }

        let endpoint = s.aiEndpoint.isEmpty ? "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions" : s.aiEndpoint
        let model = s.aiModel.isEmpty ? "gemini-2.0-flash" : s.aiModel
        guard let url = URL(string: endpoint) else { return clips }

        let lines = clips.enumerated().map { "\($0.offset + 1). \($0.element.quote)" }.joined(separator: "\n")
        let prompt = """
请将以下几句来自欧美经典影视剧的真实台词翻译为地道、口语化的简体中文，严格以 JSON 字符串数组格式返回，例如 ["中文1", "中文2"]：
\(lines)
"""

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "你是一位专业的欧美影视字幕翻译专家。请只返回 JSON 字符串数组，不要包裹额外说明。"],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return clips }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = bodyData
        req.timeoutInterval = 6

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return clips
            }

            struct ChatChoice: Decodable {
                struct Msg: Decodable { let content: String }
                let message: Msg
            }
            struct ChatResp: Decodable { let choices: [ChatChoice] }

            let decoded = try JSONDecoder().decode(ChatResp.self, from: data)
            guard var content = decoded.choices.first?.message.content else { return clips }
            content = content.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

            guard let jsonData = content.data(using: .utf8),
                  let translations = try? JSONDecoder().decode([String].self, from: jsonData) else {
                return clips
            }

            var updated = clips
            for i in 0..<min(updated.count, translations.count) {
                let trans = translations[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !trans.isEmpty {
                    let old = updated[i]
                    updated[i] = MovieSceneItem(
                        id: old.id,
                        title: old.title,
                        seasonEpisode: old.seasonEpisode,
                        character: old.character,
                        quote: old.quote,
                        translation: trans,
                        context: old.context,
                        videoURL: old.videoURL,
                        posterURL: old.posterURL,
                        isRealSoundtrack: old.isRealSoundtrack
                    )
                }
            }
            return updated
        } catch {
            return clips
        }
    }

    // MARK: - 真实影视原声播放器 (100% 播放原片音轨)
    public func playMovieAudio(scene: MovieSceneItem) {
        // 如果当前正在播放同一段音频，点按即暂停
        if currentlyPlayingClipId == scene.id {
            stopAudio()
            return
        }

        stopAudio()

        // 若为真实影视切片，直接拉取原片 MP4 音轨播放
        if scene.isRealSoundtrack, let videoURLStr = scene.videoURL, let videoURL = URL(string: videoURLStr) {
            let localFile = clipsDir.appendingPathComponent("\(scene.id).mp4")

            currentlyPlayingClipId = scene.id

            if FileManager.default.fileExists(atPath: localFile.path) {
                playLocalAudioFile(localFile)
            } else {
                isDownloadingClip = true
                Task { [weak self] in
                    guard let self = self else { return }
                    var req = URLRequest(url: videoURL)
                    req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                    req.setValue("https://yarn.co/yarn-clip/\(scene.id)", forHTTPHeaderField: "Referer")
                    req.timeoutInterval = 8

                    do {
                        let (data, resp) = try await URLSession.shared.data(for: req)
                        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                            await MainActor.run {
                                self.isDownloadingClip = false
                                self.currentlyPlayingClipId = nil
                            }
                            return
                        }
                        try data.write(to: localFile, options: .atomic)
                        await MainActor.run {
                            self.isDownloadingClip = false
                            if self.currentlyPlayingClipId == scene.id {
                                self.playLocalAudioFile(localFile)
                            }
                        }
                    } catch {
                        await MainActor.run {
                            self.isDownloadingClip = false
                            self.currentlyPlayingClipId = nil
                        }
                    }
                }
            }
        } else {
            // 纯文本兜底朗读
            currentlyPlayingClipId = scene.id
            AudioPlayer.shared.playSentence(text: scene.quote)
        }
    }

    private func playLocalAudioFile(_ fileURL: URL) {
        moviePlayer = AVPlayer(url: fileURL)
        moviePlayer?.play()
    }

    public func stopAudio() {
        moviePlayer?.pause()
        moviePlayer = nil
        AudioPlayer.shared.stop()
        currentlyPlayingClipId = nil
        isDownloadingClip = false
    }

    // MARK: - AI 影视剧台词兜底
    private func queryAIForMovieScenes(word: String) async throws -> [MovieSceneItem] {
        let s = SettingsStore.shared
        let endpoint = s.aiEndpoint.isEmpty ? "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions" : s.aiEndpoint
        let apiKey = s.aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = s.aiModel.isEmpty ? "gemini-2.0-flash" : s.aiModel

        guard !apiKey.isEmpty else {
            throw NSError(domain: "MovieScene", code: 401, userInfo: [NSLocalizedDescriptionKey: "未配置 AI API Key，请在设置中填写"])
        }
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "MovieScene", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 AI 接口地址"])
        }

        let prompt = """
请为英文词汇「\(word)」从欧美知名经典影视剧（如《绝命毒师》《老友记》《生活大爆炸》《摩登家庭》《神探夏洛克》《钢铁侠》等）中检索 3 个真实名场面台词。
台词要求：
1. 必须是完整的英文长句子（要求在 8~25 个英文单词），必须自然包含「\(word)」，严禁只输出孤立单词或一两个词的简短感叹！
2. 必须来自真实影视剧情，具有生动地道的语境。
必须严格返回 JSON 数组格式：
[
  {
    "title": "影视剧中英文名",
    "seasonEpisode": "S04E04 或 2008",
    "character": "角色名",
    "quote": "真实英文原声台词完整长句子",
    "translation": "中文对照翻译",
    "context": "剧情语境解读"
  }
]
"""

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "你是一位专业的电影学者，熟悉经典欧美影视剧真实台词。输出的台词必须是 8~25 个单词的完整对白长句子，严禁简短单字呼喊。请严格以 JSON 格式输出。"],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "MovieScene", code: 500, userInfo: [NSLocalizedDescriptionKey: "AI 影视检索失败"])
        }

        struct ChatChoice: Decodable {
            struct Msg: Decodable { let content: String }
            let message: Msg
        }
        struct ChatResp: Decodable { let choices: [ChatChoice] }

        let decoded = try JSONDecoder().decode(ChatResp.self, from: data)
        guard var content = decoded.choices.first?.message.content else { return [] }
        content = content.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

        struct RawItem: Decodable {
            let title: String?
            let seasonEpisode: String?
            let character: String?
            let quote: String?
            let translation: String?
            let context: String?
        }

        guard let jsonData = content.data(using: .utf8),
              let rawItems = try? JSONDecoder().decode([RawItem].self, from: jsonData) else {
            return []
        }

        return rawItems.compactMap { r in
            guard let q = r.quote, Self.isValidSentenceQuote(q), let tr = r.translation, !tr.isEmpty else { return nil }
            return MovieSceneItem(
                title: r.title ?? "经典欧美影视",
                seasonEpisode: r.seasonEpisode,
                character: r.character,
                quote: q,
                translation: tr,
                context: r.context,
                videoURL: nil,
                posterURL: nil,
                isRealSoundtrack: false
            )
        }
    }

    private func generateFallbackScenes(word: String) -> [MovieSceneItem] {
        return [
            MovieSceneItem(
                title: "Friends / 老友记",
                seasonEpisode: "S05E09",
                character: "Ross Geller",
                quote: "Someone at work ate my sandwich! It had a moist maker!",
                translation: "有人在单位把我的三明治吃了！那里面可是放了浸汁肉汁层面包的！",
                context: "罗斯向大家愤怒控诉自己在博物馆被同事偷吃三明治的崩溃时刻",
                isRealSoundtrack: false
            )
        ]
    }

    // MARK: - 缓存存储
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
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([MovieSceneItem].self, from: data),
              !items.isEmpty else {
            return nil
        }
        // 如果旧缓存中包含单字呼喊或不合格短台词，立即作废并移除该缓存文件，以便重新抓取长句子
        let allValid = items.allSatisfy { Self.isValidSentenceQuote($0.quote) }
        guard allValid else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return items
    }
}
