import SwiftUI

public enum HUDViewMode {
    case dictionary
    case aiChat
}

public struct HUDView: View {
    @ObservedObject var engine = DictionaryEngine.shared
    @ObservedObject var vocabStore = VocabularyStore.shared
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var chatService = AIChatService.shared

    public var onClose: () -> Void

    @State private var viewMode: HUDViewMode = .dictionary
    @State private var isEditing: Bool = false
    @State private var editingText: String = ""
    @State private var toastMessage: String? = nil
    @FocusState private var isTextFieldFocused: Bool

    public init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }

    private func commitEditing() {
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isEditing = false
        isTextFieldFocused = false
        viewMode = .dictionary
        DictionaryEngine.shared.lookup(word: trimmed, triggerSource: .manual)
    }

    private func startEditing() {
        editingText = engine.currentWord
        isEditing = true
        HUDPanel.shared.activateForEditing()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isTextFieldFocused = true
        }
    }

    private func enterAIChat(withQuestion question: String? = nil) {
        // 提取已有 AI 释义，无缝注入为对话中的第 1 条 AI 气泡
        let existingAI = engine.results.first(where: { $0.sourceId == "ai_engine" })?.aiAnalysis
            ?? engine.results.first(where: { $0.sourceId == "ai_engine" })?.definitions.first?.meaning
            ?? primaryDefinition

        let ctx = shouldShowContext ? engine.contextSentence : nil
        chatService.startChat(
            word: engine.currentWord,
            context: ctx,
            initialExplanation: existingAI,
            followUpQuestion: question
        )
        HUDPanel.shared.isInAIChat = true
        HUDPanel.shared.activateForEditing()
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            viewMode = .aiChat
        }
    }

    private func backToDictionary() {
        HUDPanel.shared.isInAIChat = false
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            viewMode = .dictionary
        }
    }

    private var isStarred: Bool {
        vocabStore.isSaved(word: engine.currentWord)
    }

    private var usPhonetic: String? {
        engine.results.compactMap { $0.phonetic }.first
    }
    private var ukPhonetic: String? {
        engine.results.compactMap { $0.phonetic_uk }.first
    }
    private var usAudioURL: String? {
        let cleanQuery = engine.currentWord.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = engine.results.first(where: { $0.word.lowercased() == cleanQuery && $0.audioURL != nil })?.audioURL {
            return exact
        }
        return engine.results.compactMap { $0.audioURL }.first(where: { $0.lowercased().contains(cleanQuery) })
    }
    private var ukAudioURL: String? {
        let cleanQuery = engine.currentWord.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = engine.results.first(where: { $0.word.lowercased() == cleanQuery && $0.audioURL_uk != nil })?.audioURL_uk {
            return exact
        }
        return engine.results.compactMap { $0.audioURL_uk }.first(where: { $0.lowercased().contains(cleanQuery) })
    }

    /// 统一定型为国际标准音标 /.../
    private var formattedPhonetic: String? {
        let raw = (settings.preferredAccent == "uk" ? (ukPhonetic ?? usPhonetic) : (usPhonetic ?? ukPhonetic))
        guard let ph = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !ph.isEmpty else { return nil }
        let inner = ph.trimmingCharacters(in: CharacterSet(charactersIn: "[]/| "))
        guard !inner.isEmpty else { return nil }
        return "/\(inner)/"
    }

    /// 语境是否合法且清晰（如含乱码、特殊符号或代码则隐藏模块）
    private var shouldShowContext: Bool {
        guard let context = engine.contextSentence, !context.isEmpty else { return false }
        return TextSniffer.isValidContextSentence(context, targetWord: engine.currentWord)
    }

    private var primaryDefinition: String {
        // 1. 优先提取高质量 AI 结构化深度解析
        if let aiRes = engine.results.first(where: { $0.sourceId == "ai_engine" }),
           let aiText = aiRes.aiAnalysis ?? aiRes.definitions.first?.meaning,
           !aiText.isEmpty {
            return aiText
        }
        // 2. 兜底提取常规词典释义
        for res in engine.results {
            if let firstDef = res.definitions.first?.meaning, !firstDef.isEmpty {
                return firstDef
            }
        }
        return "暂无释义"
    }

    private var hasAIDefinition: Bool {
        if let aiRes = engine.results.first(where: { $0.sourceId == "ai_engine" }),
           let aiText = aiRes.aiAnalysis ?? aiRes.definitions.first?.meaning,
           !aiText.isEmpty {
            return true
        }
        return false
    }

    @ViewBuilder
    private func audioButton(accent: String, label: String) -> some View {
        let isPreferred = settings.preferredAccent == accent
        Button(action: {
            AudioPlayer.shared.speak(
                text: engine.currentWord,
                audioURL: usAudioURL,
                audioURL_uk: ukAudioURL,
                accent: accent
            )
        }) {
            HStack(spacing: 3) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundColor(isPreferred ? .white : .primary.opacity(0.82))
            .background(
                isPreferred
                    ? Color.accentColor
                    : Color.primary.opacity(0.08)
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(accent == "us" ? "美式发音 (en-US)" : "英式发音 (en-GB)")
    }

    @ViewBuilder
    private var audioButtonsGroup: some View {
        if !engine.currentWord.isEmpty {
            HStack(spacing: 5) {
                if settings.preferredAccent == "uk" {
                    audioButton(accent: "uk", label: "英")
                    audioButton(accent: "us", label: "美")
                } else {
                    audioButton(accent: "us", label: "美")
                    audioButton(accent: "uk", label: "英")
                }
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - 顶栏区 (带丝滑平滑变形转场)
            if viewMode == .dictionary {
                dictionaryHeaderView
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                aiChatHeaderView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }

            if let toast = toastMessage {
                HStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(12)
                    Spacer()
                }
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            Divider().opacity(0.5)

            // MARK: - 主内容展示区 (带丝滑推拉转场)
            if viewMode == .dictionary {
                dictionaryBodyView
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                HUDInlineAIChatView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }

            // MARK: - 底栏快速状态指示与自由缩放手柄
            footerBarView
        }
        .frame(width: CGFloat(settings.hudWidth), height: CGFloat(settings.hudHeight))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            // 设置 HUDPanel Esc 处理：若在 AI 对话模式下按 Esc，则平滑退回词典释义；若在词典模式则退出
            HUDPanel.shared.onEscPressed = {
                if viewMode == .aiChat {
                    backToDictionary()
                    return true
                }
                return false
            }
        }
        .onChange(of: engine.currentWord) { newWord in
            editingText = newWord
            isEditing = false
            viewMode = .dictionary
            HUDPanel.shared.isInAIChat = false
        }
    }

    // MARK: - 词典释义模式顶栏
    private var dictionaryHeaderView: some View {
        HStack(alignment: .center, spacing: 8) {
            if isEditing {
                // 编辑模式：输入框 + 清空 + 提交 + 取消
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(.accentColor)

                    TextField("修改或输入要查询的单词、短语或句子...", text: $editingText)
                        .font(.system(size: 13, weight: .medium))
                        .textFieldStyle(.plain)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            commitEditing()
                        }

                    if !editingText.isEmpty {
                        Button(action: { editingText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: commitEditing) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("确认查词 (Return)")

                    Button(action: { isEditing = false }) {
                        Text("取消")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                )
            } else {
                // 展示模式：内容 + 编辑按钮 + 发音 + 来源
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 8) {
                        if engine.isSentence {
                            Text(engine.currentWord.isEmpty ? "MacDict" : engine.currentWord)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .onTapGesture(count: 2) {
                                    startEditing()
                                }

                            Button(action: startEditing) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .padding(3)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("修改当前内容")

                            Button(action: {
                                AudioPlayer.shared.speak(text: engine.currentWord)
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 9))
                                    Text("朗读整句")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .foregroundColor(.white)
                                .background(Color.accentColor)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .help("TTS 朗读当前整句")
                        } else {
                            Text(engine.currentWord.isEmpty ? "MacDict" : engine.currentWord)
                                .font(.system(size: engine.currentWord.count > 20 ? 16 : 20, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .onTapGesture(count: 2) {
                                    startEditing()
                                }

                            Button(action: startEditing) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .padding(3)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("修改当前词汇/短语")

                            if let ph = formattedPhonetic {
                                Text(ph)
                                    .font(.system(size: 13, design: .serif))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            audioButtonsGroup
                        }
                    }

                    if let app = engine.sourceAppName {
                        Text("来源于: \(app)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }

            Spacer()

            // 收藏生词本按钮
            Button(action: {
                let wasSaved = isStarred
                vocabStore.toggleWord(
                    word: engine.currentWord,
                    phonetic: formattedPhonetic,
                    definition: primaryDefinition,
                    context: shouldShowContext ? engine.contextSentence : nil,
                    sourceApp: engine.sourceAppName,
                    imageUrl: WordImageService.shared.currentImageURL
                )
                // 若新收录且当前尚未获取到 AI 解释，立即在后台异步请求 AI 生成深度解释并更新生词本
                if !wasSaved && !hasAIDefinition {
                    let wordToFetch = engine.currentWord
                    let ctxToFetch = shouldShowContext ? engine.contextSentence : nil
                    Task {
                        await vocabStore.requestAIDefinitionForWord(word: wordToFetch, context: ctxToFetch)
                    }
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    toastMessage = wasSaved ? "已移出生词本" : "⭐ 已收录至生词本 (优先采用 AI 解释)"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toastMessage = nil
                    }
                }
            }) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: 15))
                    .foregroundColor(isStarred ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(isStarred ? "已移出生词本" : "加入生词本")

            // 问AI 按钮 (平滑切换进入气泡问答)
            Button(action: {
                enterAIChat(withQuestion: nil)
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles.bubble.fill")
                        .font(.system(size: 11))
                    Text("问AI")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .foregroundColor(.accentColor)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("平滑进入 AI 问答对话，探讨近义词、造句与联想")

            // 在主窗口中打开
            Button(action: {
                let word = engine.currentWord
                onClose()
                MainWindowController.shared.showWindow(word: word)
            }) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("在词典主窗口中查看")

            // 关闭按钮
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - AI 问答对话模式顶栏
    private var aiChatHeaderView: some View {
        HStack(alignment: .center, spacing: 8) {
            // 左上角关闭按钮 (符合用户明确要求的左上角点击关闭)
            Button(action: {
                HUDPanel.shared.isInAIChat = false
                onClose()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help("关闭浮窗")

            // 返回词典释义按钮 (平滑推拉回词典)
            Button(action: backToDictionary) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("返回词典")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("返回词典释义列表 (Esc)")

            Text("·")
                .foregroundColor(.secondary.opacity(0.4))

            Text(engine.currentWord)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)

            Text("AI 问答")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.purple)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.12))
                .cornerRadius(4)

            Spacer()

            if !chatService.messages.isEmpty {
                Button(action: {
                    chatService.clearMessages()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("清空")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("清空当前对话记录")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - 词典多源结果滚动主体
    private var dictionaryBodyView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 原文上下文卡片 (若有且合规无乱码)
            if shouldShowContext, let context = engine.contextSentence {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                    Text(context)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.03))
                Divider().opacity(0.3)
            }

            // 多源结果卡片滚动区
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 12) {
                    ForEach(engine.results) { result in
                        SourceResultCard(result: result, onFollowUp: { q in
                            enterAIChat(withQuestion: q)
                        })
                    }

                    if engine.results.isEmpty && !engine.isSearching {
                        VStack(spacing: 8) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                            Text("未查询到释义")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 底栏快速状态指示与自由缩放手柄
    private var footerBarView: some View {
        HStack(alignment: .center) {
            if viewMode == .dictionary {
                HStack(spacing: 4) {
                    Circle()
                        .fill(settings.isHoverLookupEnabled ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text("悬停取词")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundColor(.purple)
                    Text("AI 问答对话中")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(viewMode == .dictionary ? "按 Esc 退出" : "按 Esc 退回词典")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))

            NativeHUDResizeGrip()
                .frame(width: 18, height: 18)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.02))
    }
}

// MARK: - 内嵌式 AI 问答气泡对话视图
public struct HUDInlineAIChatView: View {
    @ObservedObject var chatService = AIChatService.shared
    @State private var inputText: String = ""
    @State private var lastInputText: String = ""
    @State private var copiedId: UUID? = nil
    @FocusState private var isInputFocused: Bool

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 消息滚动区
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 10) {
                        ForEach(chatService.messages) { msg in
                            inlineMessageRow(msg)
                                .id(msg.id)
                        }

                        // 如果只有第一条（预置的 AI 初步释义），展示快捷联想启发胶囊
                        if chatService.messages.count <= 1 {
                            inlinePromptChips
                                .padding(.top, 4)
                        }

                        if chatService.isGenerating {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.6)
                                Text("AI 正在思考并组织解答...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("停止") {
                                    chatService.stopGeneration()
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            .padding(8)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                            .id("generating_indicator")
                        }

                        if let err = chatService.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(err)
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                                Spacer()
                                Button("重试") {
                                    chatService.regenerateLastMessage()
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            .padding(8)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(6)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: chatService.messages.count) { _ in
                    if let last = chatService.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: chatService.isGenerating) { isGen in
                    if isGen {
                        withAnimation { proxy.scrollTo("generating_indicator", anchor: .bottom) }
                    }
                }
            }

            Divider().opacity(0.4)

            // 底部输入栏
            HStack(alignment: .bottom, spacing: 8) {
                TextField("继续追问（如用法差别、地道造句）...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .frame(minHeight: 20)
                    .onSubmit {
                        submitInput()
                    }

                if chatService.isGenerating {
                    Button(action: { chatService.stopGeneration() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 1)
                    .help("停止生成")
                } else {
                    Button(action: submitInput) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                             ? .secondary.opacity(0.4)
                                             : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.bottom, 1)
                    .help("发送追问 (Return，Shift+Return 换行)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .onChange(of: inputText) { newValue in
                // 单击 Return (未按住 Shift) 快捷发送；按住 Shift+Return 允许换行
                if newValue.count == lastInputText.count + 1 && newValue.hasSuffix("\n") {
                    let isShift = NSEvent.modifierFlags.contains(.shift)
                    if !isShift {
                        let textToSend = String(newValue.dropLast())
                        inputText = ""
                        lastInputText = ""
                        let trimmed = textToSend.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && !chatService.isGenerating {
                            chatService.sendMessage(trimmed)
                        }
                        return
                    }
                }
                lastInputText = newValue
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }

    private func submitInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chatService.isGenerating else { return }
        inputText = ""
        chatService.sendMessage(trimmed)
    }

    @ViewBuilder
    private func inlineMessageRow(_ msg: AIChatMessage) -> some View {
        if msg.role == "user" {
            HStack {
                Spacer(minLength: 32)
                Text(msg.content)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    // 如果是第一条承接消息，带一个小标题标记
                    if msg.id == chatService.messages.first?.id {
                        HStack(spacing: 4) {
                            Text("📖 词典语境初解")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }

                    Text(msg.content)
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .foregroundColor(.primary.opacity(0.92))

                    HStack(spacing: 10) {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(msg.content, forType: .string)
                            copiedId = msg.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedId == msg.id { copiedId = nil }
                            }
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: copiedId == msg.id ? "checkmark" : "doc.on.doc")
                                Text(copiedId == msg.id ? "已复制" : "复制")
                            }
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            AudioPlayer.shared.speak(text: msg.content)
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "speaker.wave.2")
                                Text("朗读")
                            }
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.top, 2)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.85))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )

                Spacer(minLength: 16)
            }
        }
    }

    private var inlinePromptChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("💡 快捷联想启发:")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

            FlowLayout(spacing: 6) {
                inlineChip("💡 近义词辨析") {
                    chatService.sendMessage("请详细列举与【\(chatService.currentWord)】最密切的 3~4 个近义词，并清晰对比语感与适用场景差异。")
                }
                inlineChip("📝 地道场景造句") {
                    chatService.sendMessage("请为【\(chatService.currentWord)】提供 3 个不同场景下的地道例句（如商务沟通、学术论文、日常口语），并附上中文释义。")
                }
                inlineChip("🔍 高频固定搭配") {
                    chatService.sendMessage("请总结【\(chatService.currentWord)】最经典的动词/介词/形容词固定搭配与使用示例。")
                }
                inlineChip("⚠️ 易混淆词与陷阱") {
                    chatService.sendMessage("使用【\(chatService.currentWord)】时有哪些极容易混淆的形近词与常见误区？")
                }
                inlineChip("🧠 记忆法与词源") {
                    chatService.sendMessage("请拆解【\(chatService.currentWord)】的词根词缀，并提供一套生动的联想记忆法。")
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(8)
    }

    private func inlineChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .foregroundColor(.primary.opacity(0.85))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 单个词典源卡片组件
public struct SourceResultCard: View {
    public let result: DictionaryResult
    public var onFollowUp: ((String?) -> Void)? = nil

    public init(result: DictionaryResult, onFollowUp: ((String?) -> Void)? = nil) {
        self.result = result
        self.onFollowUp = onFollowUp
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 卡片标题栏
            HStack(spacing: 6) {
                Image(systemName: sourceIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(result.sourceName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                if case .loading = result.status {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }

                // 词频与考试标签
                ForEach(result.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(tagBackground(tag))
                        .foregroundColor(tagForeground(tag))
                        .cornerRadius(4)
                }
            }

            // 卡片主体内容
            switch result.status {
            case .loading:
                Text("正在查询中...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.vertical, 4)

            case .failure(let errorMsg):
                Text(errorMsg)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.vertical, 2)

            case .success, .idle:
                if result.sourceId == "ai_engine" && result.status == .idle && result.aiAnalysis == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("悬停模式下默认静默节省 AI 额度。如需深度解读当前语境，请点击：")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Button(action: {
                            DictionaryEngine.shared.triggerAIAnalysis()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                Text("深度解析此语境 (AI)")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                } else if let raw = result.rawText, result.definitions.isEmpty {
                    Text(raw)
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(.primary.opacity(0.9))
                        .lineSpacing(3)
                } else if let ai = result.aiAnalysis {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(ai))
                            .font(.system(size: 12))
                            .foregroundColor(.primary.opacity(0.95))
                            .lineSpacing(3)
                            .textSelection(.enabled)

                        if let onFollowUp = onFollowUp {
                            VStack(alignment: .leading, spacing: 4) {
                                Divider().opacity(0.4)
                                HStack(spacing: 5) {
                                    Text("向 AI 追问:")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)

                                    Button(action: {
                                        onFollowUp("请详细列举与【\(result.word)】最密切的 3~4 个近义词及语境差异。")
                                    }) {
                                        HStack(spacing: 2) {
                                            Image(systemName: "lightbulb")
                                            Text("近义辨析")
                                        }
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.06))
                                        .cornerRadius(5)
                                    }
                                    .buttonStyle(.plain)

                                    Button(action: {
                                        onFollowUp("请为【\(result.word)】提供 2 个地道实用的会话例句。")
                                    }) {
                                        HStack(spacing: 2) {
                                            Image(systemName: "pencil.and.outline")
                                            Text("场景造句")
                                        }
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.06))
                                        .cornerRadius(5)
                                    }
                                    .buttonStyle(.plain)

                                    Spacer()

                                    Button(action: {
                                        onFollowUp(nil)
                                    }) {
                                        HStack(spacing: 2) {
                                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                            Text("AI 对话 →")
                                        }
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(result.definitions) { def in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .top, spacing: 6) {
                                    Text(def.partOfSpeech)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.12))
                                        .cornerRadius(3)

                                    Text(def.meaning)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(.primary)
                                }

                                ForEach(def.exampleItems) { item in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("•")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary.opacity(0.6))

                                        Text(item.text)
                                            .font(.system(size: 11, design: .serif))
                                            .foregroundColor(.secondary)
                                            .lineSpacing(2)
                                            .textSelection(.enabled)

                                        Spacer(minLength: 4)

                                        Button(action: {
                                            AudioPlayer.shared.playSentence(text: item.text, audioURL: item.audioURL)
                                        }) {
                                            Image(systemName: item.audioURL != nil ? "speaker.wave.2.fill" : "speaker.wave.1")
                                                .font(.system(size: 9))
                                                .foregroundColor(item.audioURL != nil ? .accentColor : .secondary.opacity(0.7))
                                                .padding(3)
                                                .background(item.audioURL != nil ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .help(item.audioURL != nil ? "播放母语者原声录音" : "朗读例句 (AI神经语音)")
                                    }
                                    .padding(.leading, 10)
                                    .padding(.vertical, 1)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            result.sourceId == "ai_engine"
                ? Color.purple.opacity(0.04)
                : Color.primary.opacity(0.03)
        )
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    result.sourceId == "ai_engine"
                        ? Color.purple.opacity(0.18)
                        : Color.clear,
                    lineWidth: 1
                )
        )
    }

    private var sourceIcon: String {
        switch result.sourceId {
        case "longman": return "book.closed.fill"
        case "collins_cobuild": return "character.book.closed.fill"
        case "system_oxford": return "apple.logo"
        case "ai_engine": return "brain.head.profile"
        case "wiktionary": return "globe"
        case "free_dictionary_api": return "character.book.closed"
        default: return "book.closed"
        }
    }

    private func tagBackground(_ tag: String) -> Color {
        if tag.contains("●") {
            return Color.orange.opacity(0.16)
        } else if tag.hasPrefix("S") || tag.hasPrefix("W") {
            return Color.red.opacity(0.12)
        } else if tag.contains("★") {
            return Color.yellow.opacity(0.18)
        } else if tag.hasPrefix("CEFR") {
            return Color.teal.opacity(0.14)
        }
        return Color.accentColor.opacity(0.12)
    }

    private func tagForeground(_ tag: String) -> Color {
        if tag.contains("●") {
            return Color.orange
        } else if tag.hasPrefix("S") || tag.hasPrefix("W") {
            return Color.red
        } else if tag.contains("★") {
            return Color.orange
        } else if tag.hasPrefix("CEFR") {
            return Color.teal
        }
        return Color.accentColor
    }
}

// MARK: - 原生 Cocoa 窗口右下角自由缩放手柄（彻底杜绝与窗口拖动的冲突与高频刷新闪烁）
public struct NativeHUDResizeGrip: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> ResizeGripNSView {
        ResizeGripNSView()
    }
    public func updateNSView(_ nsView: ResizeGripNSView, context: Context) {}
}

public final class ResizeGripNSView: NSView {
    private var initialFrame: NSRect = .zero
    private var initialMouseScreen: NSPoint = .zero
    private var isDragging = false
    private let symbolView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        symbolView.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "缩放窗口")
        symbolView.contentTintColor = NSColor.secondaryLabelColor.withAlphaComponent(0.5)
        symbolView.imageScaling = .scaleProportionallyDown
        symbolView.frame = bounds
        symbolView.autoresizingMask = [.width, .height]
        addSubview(symbolView)
    }

    override public func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override public func mouseDown(with event: NSEvent) {
        guard let window = self.window as? HUDPanel else { return }
        isDragging = true
        window.isResizing = true
        window.isMovableByWindowBackground = false
        initialFrame = window.frame
        initialMouseScreen = NSEvent.mouseLocation
        symbolView.contentTintColor = NSColor.controlAccentColor
    }

    override public func mouseDragged(with event: NSEvent) {
        guard isDragging, let window = self.window as? HUDPanel else { return }
        let currentMouse = NSEvent.mouseLocation
        let dx = currentMouse.x - initialMouseScreen.x
        let dy = currentMouse.y - initialMouseScreen.y

        let newWidth = max(380, min(850, initialFrame.width + dx))
        let newHeight = max(320, min(950, initialFrame.height - dy))

        window.updateSize(width: newWidth, height: newHeight)
    }

    override public func mouseUp(with event: NSEvent) {
        guard isDragging, let window = self.window as? HUDPanel else { return }
        isDragging = false
        window.isResizing = false
        window.isMovableByWindowBackground = true
        symbolView.contentTintColor = NSColor.secondaryLabelColor.withAlphaComponent(0.5)

        let finalW = Double(window.frame.width)
        let finalH = Double(window.frame.height)
        SettingsStore.shared.hudWidth = finalW
        SettingsStore.shared.hudHeight = finalH
    }
}
