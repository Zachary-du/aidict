import Foundation
import SwiftUI
import Combine

public struct AIChatMessage: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let role: String  // "user" | "assistant" | "system"
    public var content: String
    public let timestamp: Date

    public init(id: UUID = UUID(), role: String, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

@MainActor
public final class AIChatService: ObservableObject {
    public static let shared = AIChatService()

    @Published public var messages: [AIChatMessage] = []
    @Published public var isGenerating: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var currentWord: String = ""
    @Published public var contextSentence: String? = nil

    private var activeTask: Task<Void, Never>?

    private init() {}

    /// 启动一个针对指定词条/语境的对话
    /// - Parameters:
    ///   - word: 当前词条
    ///   - context: 取词时的语境句子
    ///   - initialExplanation: AI 之前对该词的初步释义（无缝作为第一条 AI 气泡承接）
    ///   - followUpQuestion: 可选的立即自动触发的问题（如点击了“同义词辨析”）
    public func startChat(
        word: String,
        context: String? = nil,
        initialExplanation: String? = nil,
        followUpQuestion: String? = nil
    ) {
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSameWord = (cleanWord == currentWord && !messages.isEmpty)

        if !isSameWord {
            self.currentWord = cleanWord
            self.contextSentence = context
            self.messages = []
            self.errorMessage = nil

            // 核心承接：将查词时已有的 AI 释义无缝注入为第一条 AI 气泡
            if let explanation = initialExplanation?.trimmingCharacters(in: .whitespacesAndNewlines), !explanation.isEmpty {
                let firstMsg = AIChatMessage(role: "assistant", content: explanation)
                self.messages.append(firstMsg)
            }
        } else if let ctx = context, !ctx.isEmpty {
            self.contextSentence = ctx
        }

        if let question = followUpQuestion, !question.isEmpty {
            sendMessage(question)
        }
    }

    /// 发送用户提问
    public func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 追加用户消息
        let userMsg = AIChatMessage(role: "user", content: trimmed)
        messages.append(userMsg)
        errorMessage = nil
        isGenerating = true

        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self = self else { return }
            await self.performChatCompletion()
        }
    }

    /// 重新生成最后一条 AI 回复
    public func regenerateLastMessage() {
        guard !messages.isEmpty else { return }
        if messages.last?.role == "assistant" {
            messages.removeLast()
        }
        guard messages.contains(where: { $0.role == "user" }) else { return }

        isGenerating = true
        errorMessage = nil

        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self = self else { return }
            await self.performChatCompletion()
        }
    }

    /// 停止生成
    public func stopGeneration() {
        activeTask?.cancel()
        activeTask = nil
        isGenerating = false
    }

    /// 清空会话
    public func clearMessages() {
        stopGeneration()
        messages.removeAll()
        errorMessage = nil
    }

    // MARK: - 网络请求实现
    private func performChatCompletion() async {
        let settings = SettingsStore.shared
        let endpoint = settings.aiEndpoint.isEmpty
            ? "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
            : settings.aiEndpoint
        let apiKey = settings.aiApiKey
        let model = settings.aiModel.isEmpty ? "gemini-2.0-flash" : settings.aiModel

        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            self.errorMessage = "未检测到 AI API Key，请在「设置」->「AI 语境配置」中填写 Key。"
            self.isGenerating = false
            return
        }

        guard let url = URL(string: endpoint) else {
            self.errorMessage = "无效的 AI 接口地址: \(endpoint)"
            self.isGenerating = false
            return
        }

        // 构建 System Prompt 强化语言学和词典辅导专长
        var systemPrompt = "你是一位极富耐心、博学且精通多国语言的语言学教授与英语辅导专家。"
        if !currentWord.isEmpty {
            systemPrompt += " 用户当前正在深入探讨词汇或短语：【\(currentWord)】。"
            if let ctx = contextSentence, !ctx.isEmpty {
                systemPrompt += " 捕获的实际使用语境为：\"\(ctx)\"。"
            }
        }
        systemPrompt += """
 用户可能会向你咨询同义词辨析、使用场景、地道造句、搭配用法、易错点、词源故事或任何发散联想。
请遵循以下回答准则：
1. 条理清晰，善用清晰的 Markdown 标头、粗体和列表。
2. 解释力求简练精准、直击要害，重点说明用法差别和语境语感。
3. 给出的英文例句必须配有自然地道的中文释义。
4. 语言风格亲切专业，避免无意义的客套废话。
"""

        // 构建消息历史
        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        for msg in messages {
            apiMessages.append(["role": msg.role, "content": msg.content])
        }

        let requestBody: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.5,
            "max_tokens": 1500
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.errorMessage = "网络连接异常，未收到有效响应"
                self.isGenerating = false
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                self.errorMessage = "请求失败 (HTTP \(httpResponse.statusCode)): \(errText)"
                self.isGenerating = false
                return
            }

            struct ChatChoice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            struct ChatCompletion: Decodable { let choices: [ChatChoice] }

            let completion = try JSONDecoder().decode(ChatCompletion.self, from: data)
            guard let reply = completion.choices.first?.message.content, !reply.isEmpty else {
                self.errorMessage = "AI 返回的内容为空"
                self.isGenerating = false
                return
            }

            let assistantMsg = AIChatMessage(role: "assistant", content: reply.trimmingCharacters(in: .whitespacesAndNewlines))
            self.messages.append(assistantMsg)
            self.isGenerating = false
        } catch {
            guard !Task.isCancelled else { return }
            self.errorMessage = "请求出错: \(error.localizedDescription)"
            self.isGenerating = false
        }
    }
}
