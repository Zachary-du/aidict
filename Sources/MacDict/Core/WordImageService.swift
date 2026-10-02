import AppKit
import Foundation

/// 单词插画与图解检索服务
/// 支持本地永久磁盘缓存、Pixabay 插画 API 检索，以及 Wikipedia 官方即时缩略图免 Key 智能降级兜底
public final class WordImageService: ObservableObject, @unchecked Sendable {
    public static let shared = WordImageService()

    @Published public var currentImage: NSImage? = nil
    @Published public var currentImageURL: String? = nil
    @Published public var currentWord: String = ""
    @Published public var isLoading: Bool = false

    private let memoryCache = NSCache<NSString, NSImage>()
    private let diskCacheDirectory: URL
    private let session: URLSession

    private var activeTask: Task<Void, Never>?
    private let lock = NSLock()
    private var inFlightWords: Set<String> = []

    private init() {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskCacheDirectory = cachesURL.appendingPathComponent("MacDict/WordImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 8.0
        self.session = URLSession(configuration: config)

        memoryCache.countLimit = 150
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    // MARK: - 主入口：检索单词插画（支持任意线程调用）
    public func lookupImage(for rawWord: String) {
        let trimmed = rawWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            Task { @MainActor in
                self.currentImage = nil
                self.currentImageURL = nil
                self.currentWord = ""
                self.isLoading = false
            }
            return
        }

        // 整句或超长文本无需匹配单个单词插画
        let wordCount = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        if wordCount >= 5 {
            Task { @MainActor in
                self.currentImage = nil
                self.currentImageURL = nil
                self.currentWord = trimmed
                self.isLoading = false
            }
            return
        }

        // 1. 尝试从内存缓存命中 (0 延迟)
        if let cached = memoryCache.object(forKey: trimmed as NSString) {
            Task { @MainActor in
                self.currentWord = trimmed
                self.currentImage = cached
                self.isLoading = false
            }
            return
        }

        // 2. 尝试从本地磁盘缓存命中 (毫秒级直出，0 延迟)
        if let diskImage = loadFromDiskCache(word: trimmed) {
            memoryCache.setObject(diskImage, forKey: trimmed as NSString)
            Task { @MainActor in
                self.currentWord = trimmed
                self.currentImage = diskImage
                self.isLoading = false
            }
            return
        }

        // 3. 异步并发拉取
        Task { @MainActor in
            self.currentWord = trimmed
            self.currentImage = nil
            self.currentImageURL = nil
            self.isLoading = true
        }

        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self = self else { return }
            let (image, urlStr) = await self.fetchImageAsync(for: trimmed)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                if self.currentWord == trimmed {
                    self.currentImage = image
                    self.currentImageURL = urlStr
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - 同步读取本地缓存（供生词本列表等无缝快速加载）
    public func getCachedImage(for rawWord: String) -> NSImage? {
        let trimmed = rawWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if let mem = memoryCache.object(forKey: trimmed as NSString) {
            return mem
        }
        if let disk = loadFromDiskCache(word: trimmed) {
            memoryCache.setObject(disk, forKey: trimmed as NSString)
            return disk
        }
        return nil
    }

    private func tryBeginInFlight(word: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if inFlightWords.contains(word) { return false }
        inFlightWords.insert(word)
        return true
    }

    private func finishInFlight(word: String) {
        lock.lock()
        defer { lock.unlock() }
        inFlightWords.remove(word)
    }

    // MARK: - 核心异步抓取流水线
    public func fetchImageAsync(for word: String) async -> (image: NSImage?, url: String?) {
        let sanitized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !sanitized.isEmpty else { return (nil, nil) }

        // 去重并发请求
        if !tryBeginInFlight(word: sanitized) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let img = getCachedImage(for: sanitized) {
                return (img, nil)
            }
            return (nil, nil)
        }

        defer {
            finishInFlight(word: sanitized)
        }

        // 步骤 1: 优先尝试 Pixabay 插画 API
        let pixabayKey = SettingsStore.shared.pixabayApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pixabayKey.isEmpty {
            if let (img, url) = await tryFetchPixabay(word: sanitized, apiKey: pixabayKey) {
                return (img, url)
            }
        }

        // 步骤 2: Wikipedia Summary 官方快速缩略图
        if let (img, url) = await tryFetchWikipediaSummary(word: sanitized) {
            return (img, url)
        }

        // 步骤 3: Openverse 官方免 Key 8亿图库（对各类动词、抽象词如 dedicate 极度友好）
        if let (img, url) = await tryFetchOpenverse(word: sanitized) {
            return (img, url)
        }

        // 步骤 4: Wikipedia Search Generator API 兜底（处理消歧义页或无直接缩略图词汇）
        if let (img, url) = await tryFetchWikipediaSearch(word: sanitized) {
            return (img, url)
        }

        // 步骤 5: Wikimedia Commons 媒体库兜底
        if let (img, url) = await tryFetchWikimediaCommons(word: sanitized) {
            return (img, url)
        }

        return (nil, nil)
    }

    // MARK: - Pixabay API 抓取
    private func tryFetchPixabay(word: String, apiKey: String) async -> (NSImage, String)? {
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        // 限定插画 (illustration)，精选横向/方图，开启安全搜索
        let urlString = "https://pixabay.com/api/?key=\(apiKey)&q=\(encodedWord)&image_type=illustration&safesearch=true&per_page=3"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }

            struct PixabayHit: Decodable {
                let webformatURL: String?
                let previewURL: String?
            }
            struct PixabayResponse: Decodable {
                let totalHits: Int?
                let hits: [PixabayHit]
            }

            let decoded = try JSONDecoder().decode(PixabayResponse.self, from: data)
            guard let hit = decoded.hits.first, let imgUrlStr = hit.webformatURL ?? hit.previewURL, let imgURL = URL(string: imgUrlStr) else {
                return nil
            }

            if let image = await downloadAndCache(from: imgURL, word: word) {
                aLog("WordImageService: Pixabay 插画获取成功 [\(word)]")
                return (image, imgUrlStr)
            }
        } catch {
            aLog("WordImageService: Pixabay 请求异常 [\(word)]: \(error.localizedDescription)", level: .error)
        }
        return nil
    }

    // MARK: - Wikipedia 即时 Summary 抓取 (免 Key 兜底)
    private func tryFetchWikipediaSummary(word: String) async -> (NSImage, String)? {
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        let urlString = "https://en.wikipedia.org/api/rest_v1/page/summary/\(encodedWord)"
        guard let url = URL(string: urlString) else { return nil }

        var req = URLRequest(url: url)
        req.setValue("MacDict/1.0 (https://github.com/dylan/MacDict; macdict@example.com)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }

            struct WikiThumbnail: Decodable {
                let source: String?
            }
            struct WikiSummary: Decodable {
                let thumbnail: WikiThumbnail?
                let originalimage: WikiThumbnail?
            }

            let summary = try JSONDecoder().decode(WikiSummary.self, from: data)
            // 优先使用清晰度更高的原图以适配更大尺寸的示意图展示；若仅有缩略图，则自动提质到 800px
            var targetUrlStr = summary.originalimage?.source ?? summary.thumbnail?.source
            if let raw = targetUrlStr, raw.contains("/commons/thumb/") {
                if let range = raw.range(of: #"\/\d+px-"#, options: .regularExpression) {
                    targetUrlStr = raw.replacingCharacters(in: range, with: "/800px-")
                }
            }
            guard let imgUrlStr = targetUrlStr, let imgURL = URL(string: imgUrlStr) else {
                return nil
            }

            if let image = await downloadAndCache(from: imgURL, word: word) {
                aLog("WordImageService: Wikipedia 示意图获取成功 [\(word)]")
                return (image, imgUrlStr)
            }
        } catch {
            aLog("WordImageService: Wikipedia Summary 请求异常 [\(word)]: \(error.localizedDescription)", level: .error)
        }
        return nil
    }

    // MARK: - Openverse 开放媒体检索 (免 Key，涵盖 8 亿+ 概念图片与插图)
    private func tryFetchOpenverse(word: String) async -> (NSImage, String)? {
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let urlString = "https://api.openverse.org/v1/images/?q=\(encodedWord)&page_size=3"
        guard let url = URL(string: urlString) else { return nil }

        var req = URLRequest(url: url)
        req.setValue("MacDict/1.0 (https://github.com/dylan/MacDict)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }

            struct OpenverseItem: Decodable {
                let thumbnail: String?
                let url: String?
            }
            struct OpenverseResponse: Decodable {
                let results: [OpenverseItem]?
            }

            let resp = try JSONDecoder().decode(OpenverseResponse.self, from: data)
            guard let hits = resp.results, !hits.isEmpty else { return nil }

            for item in hits {
                if let targetStr = item.thumbnail ?? item.url, let imgURL = URL(string: targetStr) {
                    if let image = await downloadAndCache(from: imgURL, word: word) {
                        aLog("WordImageService: Openverse 概念图片获取成功 [\(word)]")
                        return (image, targetStr)
                    }
                }
            }
        } catch {
            aLog("WordImageService: Openverse 请求异常 [\(word)]: \(error.localizedDescription)", level: .error)
        }
        return nil
    }

    // MARK: - Wikipedia MediaWiki Generator 搜索 (免 Key)
    private func tryFetchWikipediaSearch(word: String) async -> (NSImage, String)? {
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let urlString = "https://en.wikipedia.org/w/api.php?action=query&generator=search&gsrsearch=\(encodedWord)&gsrlimit=3&prop=pageimages&pithumbsize=640&format=json"
        guard let url = URL(string: urlString) else { return nil }

        var req = URLRequest(url: url)
        req.setValue("MacDict/1.0 (https://github.com/dylan/MacDict; macdict@example.com)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }

            struct PageItem: Decodable {
                struct Thumb: Decodable { let source: String? }
                let thumbnail: Thumb?
            }
            struct QueryData: Decodable {
                let pages: [String: PageItem]?
            }
            struct MWResponse: Decodable {
                let query: QueryData?
            }

            let mw = try JSONDecoder().decode(MWResponse.self, from: data)
            guard let pages = mw.query?.pages else { return nil }

            for (_, page) in pages {
                if var src = page.thumbnail?.source {
                    if src.contains("/commons/thumb/"), let range = src.range(of: #"\/\d+px-"#, options: .regularExpression) {
                        src = src.replacingCharacters(in: range, with: "/800px-")
                    }
                    if let imgURL = URL(string: src) {
                        if let image = await downloadAndCache(from: imgURL, word: word) {
                            aLog("WordImageService: Wikipedia Search 示意图获取成功 [\(word)]")
                            return (image, src)
                        }
                    }
                }
            }
        } catch {
            aLog("WordImageService: Wikipedia Search 请求异常 [\(word)]: \(error.localizedDescription)", level: .error)
        }
        return nil
    }

    // MARK: - Wikimedia Commons 搜索 (免 Key)
    private func tryFetchWikimediaCommons(word: String) async -> (NSImage, String)? {
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let urlString = "https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=\(encodedWord)&gsrlimit=3&prop=pageimages&pithumbsize=640&format=json"
        guard let url = URL(string: urlString) else { return nil }

        var req = URLRequest(url: url)
        req.setValue("MacDict/1.0 (https://github.com/dylan/MacDict; macdict@example.com)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }

            struct PageItem: Decodable {
                struct Thumb: Decodable { let source: String? }
                let thumbnail: Thumb?
            }
            struct QueryData: Decodable {
                let pages: [String: PageItem]?
            }
            struct MWResponse: Decodable {
                let query: QueryData?
            }

            let mw = try JSONDecoder().decode(MWResponse.self, from: data)
            guard let pages = mw.query?.pages else { return nil }

            for (_, page) in pages {
                if var src = page.thumbnail?.source {
                    if src.contains("/commons/thumb/"), let range = src.range(of: #"\/\d+px-"#, options: .regularExpression) {
                        src = src.replacingCharacters(in: range, with: "/800px-")
                    }
                    if let imgURL = URL(string: src) {
                        if let image = await downloadAndCache(from: imgURL, word: word) {
                            aLog("WordImageService: Wikimedia Commons 获取成功 [\(word)]")
                            return (image, src)
                        }
                    }
                }
            }
        } catch {
            aLog("WordImageService: Wikimedia Commons 请求异常 [\(word)]: \(error.localizedDescription)", level: .error)
        }
        return nil
    }

    // MARK: - 下载并本地持久化
    private func downloadAndCache(from url: URL, word: String) async -> NSImage? {
        do {
            var req = URLRequest(url: url)
            req.setValue("MacDict/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else {
                return nil
            }

            guard let image = NSImage(data: data) else { return nil }

            // 存入内存缓存
            memoryCache.setObject(image, forKey: word as NSString)

            // 写入本地磁盘缓存
            let diskFile = diskCacheURL(for: word)
            try? data.write(to: diskFile, options: .atomic)

            return image
        } catch {
            return nil
        }
    }

    // MARK: - 磁盘缓存工具
    private func diskCacheURL(for word: String) -> URL {
        let safeName = word.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? word
        return diskCacheDirectory.appendingPathComponent("\(safeName).img")
    }

    private func loadFromDiskCache(word: String) -> NSImage? {
        let file = diskCacheURL(for: word)
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let img = NSImage(data: data) else {
            return nil
        }
        return img
    }

    /// 清空所有缓存
    public func clearCache() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheDirectory)
        try? FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
    }
}
