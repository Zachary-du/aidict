import Foundation

public final class AIDictionarySource: DictionarySource, @unchecked Sendable {
    public let id = "ai_engine"
    public let name = "AI 语境解析"
    public let icon = "sparkles"
    public let priority = 4

    // 每个请求使用独立 URLSession，便于精确取消
    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10   // 10s，原15s太长
        cfg.timeoutIntervalForResource = 12
        return URLSession(configuration: cfg)
    }

    public init() {}

    public func lookup(word: String, context: String? = nil) async throws -> DictionaryResult {
        let s = SettingsStore.shared
        let endpoint = s.aiEndpoint.isEmpty
            ? "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
            : s.aiEndpoint
        let apiKey = s.aiApiKey
        let model = s.aiModel.isEmpty ? "gemini-2.0-flash" : s.aiModel

        aLog("AI查词 '\(word)' — model=\(model) keyLen=\(apiKey.count)")

        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NSError(domain: "AIDict", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "未配置 AI API Key，请在设置中填写"])
        }

        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "AIDict", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无效的 AI 接口地址"])
        }

        // 构建提示词（支持用户自定义）
        let prompt = buildPrompt(word: word, context: context)
        let defaultSystemPrompt = "你是一位精通英语的语言学专家。请用简洁清晰的中文解析词汇，重点突出语境含义，避免冗长废话。回复控制在200字以内。"
        let systemPrompt = s.aiSystemPrompt.isEmpty ? defaultSystemPrompt : s.aiSystemPrompt

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 500
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // 支持 Swift Task 取消时立即中断网络请求
        let session = makeSession()
        let (data, response) = try await withTaskCancellationHandler {
            try await session.data(for: request)
        } onCancel: {
            session.invalidateAndCancel()
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errText = String(data: data, encoding: .utf8) ?? "HTTP 错误"
            aLog("AI 请求失败: \(errText)", level: .error)
            throw NSError(domain: "AIDict", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "AI 请求失败: \(errText)"])
        }

        struct ChatChoice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        struct ChatCompletion: Decodable { let choices: [ChatChoice] }

        let completion = try JSONDecoder().decode(ChatCompletion.self, from: data)
        guard let aiText = completion.choices.first?.message.content else {
            throw NSError(domain: "AIDict", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "AI 返回结果为空"])
        }

        return DictionaryResult(
            sourceId: id,
            sourceName: name,
            word: word,
            definitions: [DefinitionItem(partOfSpeech: "AI 解析", meaning: aiText)],
            aiAnalysis: aiText,
            status: .success
        )
    }

    public func buildPrompt(word: String, context: String? = nil) -> String {
        let s = SettingsStore.shared
        // 若用户设置了自定义用户提示词模板，使用模板（支持 {word} 和 {context} 占位符）
        if !s.aiUserPromptTemplate.isEmpty {
            return s.aiUserPromptTemplate
                .replacingOccurrences(of: "{word}", with: word)
                .replacingOccurrences(of: "{context}", with: context ?? "")
        }

        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        let isSentence = wordCount >= 6 || trimmed.contains(". ") || trimmed.contains("? ") || trimmed.contains("! ") ||
                         trimmed.hasSuffix(".") || trimmed.hasSuffix("?") || trimmed.hasSuffix("!")

        if isSentence {
            return """
            请对以下英文句子进行专业解析：
            「\(trimmed)」

            1. 地道中文翻译
            2. 重点词汇/短语提炼（附简要释义与音标）
            3. 核心句型或语法要点简析（简洁明了）
            """
        } else if wordCount >= 2 {
            return """
            请对英文短语/习惯表达「\(trimmed)」进行专业解析：
            1. 核心中文含义与常见搭配
            2. 地道例句（带中文对照）
            3. 易混淆表达或使用建议
            """
        }

        // 默认单单词提示词：精炼、清晰、简明
        var prompt = """
        请对「\(word)」进行精炼解析：
        1. 词性与音标
        2. 核心中文释义（2~3条）
        """
        if let ctx = context, !ctx.trimmingCharacters(in: .whitespaces).isEmpty {
            prompt += """
            \n3. 【语境】该词出现在以下句子中：
            「\(ctx)」
            请指出此处确切含义并给出地道翻译。
            """
        } else {
            prompt += "\n3. 最地道的现代例句（1~2条）及中文对照。"
        }
        return prompt
    }
}
