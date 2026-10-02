import SwiftUI

public struct MainWindowView: View {
    @ObservedObject var engine = DictionaryEngine.shared
    @ObservedObject var historyStore = HistoryStore.shared
    @ObservedObject var vocabStore = VocabularyStore.shared
    @ObservedObject var settings = SettingsStore.shared

    @State private var searchText = ""
    @State private var searchSuggestions: [String] = []
    @State private var navigationStack: [String] = []
    @State private var currentIndex: Int = -1

    public init() {}

    private var currentWord: String {
        engine.currentWord
    }

    private var isStarred: Bool {
        vocabStore.isSaved(word: currentWord)
    }

    private var canGoBack: Bool {
        currentIndex > 0
    }

    private var canGoForward: Bool {
        currentIndex >= 0 && currentIndex < navigationStack.count - 1
    }

    private var usPhonetic: String? {
        engine.results.compactMap { $0.phonetic }.first
    }

    private var ukPhonetic: String? {
        engine.results.compactMap { $0.phonetic_uk }.first
    }

    private var usAudioURL: String? {
        let cleanQuery = currentWord.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = engine.results.first(where: { $0.word.lowercased() == cleanQuery && $0.audioURL != nil })?.audioURL {
            return exact
        }
        return engine.results.compactMap { $0.audioURL }.first(where: { $0.lowercased().contains(cleanQuery) })
    }

    private var ukAudioURL: String? {
        let cleanQuery = currentWord.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = engine.results.first(where: { $0.word.lowercased() == cleanQuery && $0.audioURL_uk != nil })?.audioURL_uk {
            return exact
        }
        return engine.results.compactMap { $0.audioURL_uk }.first(where: { $0.lowercased().contains(cleanQuery) })
    }

    private var formattedPhonetic: String? {
        let raw = (settings.preferredAccent == "uk" ? (ukPhonetic ?? usPhonetic) : (usPhonetic ?? ukPhonetic))
        guard let ph = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !ph.isEmpty else { return nil }
        let inner = ph.trimmingCharacters(in: CharacterSet(charactersIn: "[]/| "))
        guard !inner.isEmpty else { return nil }
        return "/\(inner)/"
    }

    private var lookupCount: Int {
        historyStore.lookupCount(for: currentWord)
    }

    public var body: some View {
        HSplitView {
            // MARK: - 左侧边栏 (搜索 + 联想词 + 历史记录)
            sidebarView
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

            // MARK: - 右侧详情区 (导航条 + 单词信息 + 多词典内容)
            detailView
                .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 520)
        .onAppear {
            if !engine.currentWord.isEmpty {
                pushWord(engine.currentWord, fetch: false)
            } else if let first = historyStore.items.first?.word {
                navigateTo(word: first)
            }
        }
    }

    // MARK: - 左侧边栏视图
    private var sidebarView: some View {
        VStack(spacing: 0) {
            // 顶部搜索框
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                TextField("搜索词条或中文释义...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            navigateTo(word: searchText)
                        }
                    }
                    .onChange(of: searchText) { newValue in
                        updateSuggestions(for: newValue)
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchSuggestions = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(12)

            Divider()

            // 搜索联想 vs 历史记录
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // 搜索联想词列表
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("词条检索 (\(searchSuggestions.count))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)

                    if searchSuggestions.isEmpty {
                        VStack(spacing: 8) {
                            Text("按回车直接查询「\(searchText)」")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(searchSuggestions, id: \.self) { word in
                            HStack {
                                Text(word)
                                    .font(.system(size: 13))
                                    .foregroundColor(word.lowercased() == currentWord.lowercased() ? .accentColor : .primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                            .onTapGesture {
                                navigateTo(word: word)
                            }
                        }
                        .listStyle(.sidebar)
                    }
                }
            } else {
                // 查词历史记录列表
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("查词历史 (\(historyStore.items.count))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        if !historyStore.items.isEmpty {
                            Button(action: { historyStore.clearAll() }) {
                                Text("清空")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)

                    if historyStore.items.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("暂无查词记录")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(historyStore.items) { item in
                            HStack(alignment: .center, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(item.word)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(item.word.lowercased() == currentWord.lowercased() ? .accentColor : .primary)

                                        if item.lookupCount > 1 {
                                            Text("第\(item.lookupCount)次")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(.accentColor)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.accentColor.opacity(0.12))
                                                .cornerRadius(3)
                                        }
                                    }

                                    if !item.summary.isEmpty {
                                        Text(item.summary)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Button(action: { historyStore.deleteItem(id: item.id) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                            .onTapGesture {
                                navigateTo(word: item.word)
                            }
                        }
                        .listStyle(.sidebar)
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - 右侧主详情区
    private var detailView: some View {
        VStack(spacing: 0) {
            // MARK: 顶部导航条
            HStack(spacing: 12) {
                // 后退与前进箭头
                HStack(spacing: 4) {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoBack)
                    .opacity(canGoBack ? 1.0 : 0.4)
                    .help("后退到上一词条 (⌘[)")

                    Button(action: goForward) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoForward)
                    .opacity(canGoForward ? 1.0 : 0.4)
                    .help("前进到下一词条 (⌘])")
                }

                Spacer()

                if !currentWord.isEmpty {
                    // 发音按钮
                    Button(action: {
                        AudioPlayer.shared.speak(
                            text: currentWord,
                            audioURL: usAudioURL,
                            audioURL_uk: ukAudioURL,
                            accent: settings.preferredAccent
                        )
                    }) {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 13))
                            .foregroundColor(.accentColor)
                            .frame(width: 28, height: 28)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("朗读单词")

                    // 收藏生词本按钮
                    Button(action: toggleStar) {
                        Image(systemName: isStarred ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundColor(isStarred ? .yellow : .secondary)
                            .frame(width: 28, height: 28)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(isStarred ? "已移出生词本" : "收录至生词本")

                    // AI 智能问答对话
                    Button(action: {
                        AIChatWindowController.shared.show(
                            word: currentWord,
                            context: engine.contextSentence
                        )
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles.bubble.fill")
                                .font(.system(size: 12))
                            Text("AI 对话")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("与 AI 深度探讨该词的同义词、搭配与造句 (⌥⌘A)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // MARK: 词条详情展示区
            if currentWord.isEmpty {
                welcomeEmptyView
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        // 单词大标题 + 音标 + 标签
                        VStack(alignment: .leading, spacing: 8) {
                            Text(currentWord)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)

                            HStack(spacing: 12) {
                                // 英音
                                if let ukPh = ukPhonetic ?? formattedPhonetic {
                                    Button(action: {
                                        AudioPlayer.shared.speak(text: currentWord, audioURL: usAudioURL, audioURL_uk: ukAudioURL, accent: "uk")
                                    }) {
                                        HStack(spacing: 4) {
                                            Text("英").font(.system(size: 11, weight: .bold))
                                            Text(ukPh).font(.system(size: 12, design: .serif))
                                            Image(systemName: "speaker.wave.2.fill").font(.system(size: 9))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.06))
                                        .cornerRadius(6)
                                        .foregroundColor(.primary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                // 美音
                                if let usPh = usPhonetic ?? formattedPhonetic {
                                    Button(action: {
                                        AudioPlayer.shared.speak(text: currentWord, audioURL: usAudioURL, audioURL_uk: ukAudioURL, accent: "us")
                                    }) {
                                        HStack(spacing: 4) {
                                            Text("美").font(.system(size: 11, weight: .bold))
                                            Text(usPh).font(.system(size: 12, design: .serif))
                                            Image(systemName: "speaker.wave.2.fill").font(.system(size: 9))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.06))
                                        .cornerRadius(6)
                                        .foregroundColor(.primary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                if lookupCount > 1 {
                                    Text("第 \(lookupCount) 次查询")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                        Divider().padding(.horizontal, 24)

                        // 各词典结果卡片流
                        LazyVStack(spacing: 16) {
                            ForEach(engine.results) { result in
                                MainSourceResultCard(result: result)
                            }

                            if engine.results.isEmpty && !engine.isSearching {
                                VStack(spacing: 8) {
                                    Image(systemName: "text.magnifyingglass")
                                        .font(.system(size: 36))
                                        .foregroundColor(.secondary)
                                    Text("未查询到释义")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 180)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - 欢迎空状态页面
    private var welcomeEmptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 56))
                .foregroundColor(.accentColor.opacity(0.8))

            Text("MacDict 桌面查词")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text("在左上角输入任意英文单词即可开始查询，或在屏幕上选中文字按 ⌥D 查词。")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            if !historyStore.items.isEmpty {
                VStack(spacing: 8) {
                    Text("最近查过：")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        ForEach(historyStore.items.prefix(5)) { item in
                            Button(action: { navigateTo(word: item.word) }) {
                                Text(item.word)
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 导航与查词逻辑
    private func navigateTo(word: String) {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        // 如果等于当前词条且已查过，直接跳过
        if currentIndex >= 0 && currentIndex < navigationStack.count && navigationStack[currentIndex].lowercased() == clean.lowercased() {
            return
        }

        pushWord(clean, fetch: true)
    }

    private func pushWord(_ word: String, fetch: Bool) {
        if currentIndex >= 0 && currentIndex < navigationStack.count - 1 {
            navigationStack = Array(navigationStack.prefix(currentIndex + 1))
        }
        navigationStack.append(word)
        currentIndex = navigationStack.count - 1

        if fetch {
            DictionaryEngine.shared.lookup(word: word, triggerSource: .manual)
        }
    }

    private func goBack() {
        guard canGoBack else { return }
        currentIndex -= 1
        let word = navigationStack[currentIndex]
        DictionaryEngine.shared.lookup(word: word, triggerSource: .manual)
    }

    private func goForward() {
        guard canGoForward else { return }
        currentIndex += 1
        let word = navigationStack[currentIndex]
        DictionaryEngine.shared.lookup(word: word, triggerSource: .manual)
    }

    private func toggleStar() {
        guard !currentWord.isEmpty else { return }
        let wasSaved = vocabStore.isSaved(word: currentWord)
        let aiDef = engine.results.first(where: { $0.sourceId == "ai_engine" })?.aiAnalysis
            ?? engine.results.first(where: { $0.sourceId == "ai_engine" })?.definitions.first?.meaning
        let firstDef = aiDef ?? engine.results.first?.definitions.first?.meaning ?? "暂无释义"
        vocabStore.toggleWord(
            word: currentWord,
            phonetic: formattedPhonetic,
            definition: firstDef,
            context: nil,
            sourceApp: nil
        )
        if !wasSaved && aiDef == nil {
            let word = currentWord
            Task {
                await vocabStore.requestAIDefinitionForWord(word: word)
            }
        }
    }

    private func updateSuggestions(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchSuggestions = []
            return
        }
        Task.detached(priority: .userInitiated) {
            let matches = CustomDictionaryStore.shared.searchPrefix(query: trimmed, limit: 30)
            await MainActor.run {
                searchSuggestions = matches
            }
        }
    }
}

// MARK: - 主窗口专用词典卡片展示组件
struct MainSourceResultCard: View {
    let result: DictionaryResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 词典头部栏
            HStack(spacing: 8) {
                Image(systemName: iconForSource(result.sourceId))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text(result.sourceName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                if case .loading = result.status {
                    ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                }

                ForEach(result.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tagBackground(tag))
                        .foregroundColor(tagForeground(tag))
                        .cornerRadius(4)
                }
            }

            // 词典卡片内容
            switch result.status {
            case .loading:
                Text("正在查询中...")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.vertical, 4)

            case .failure(let msg):
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.vertical, 2)

            case .success, .idle:
                if result.sourceId == "ai_engine" && result.status == .idle && result.aiAnalysis == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("点击下方按钮发起 AI 深度语义解析：")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Button(action: {
                            DictionaryEngine.shared.triggerAIAnalysis()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                Text("生成 AI 语境深度解析")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                } else if let raw = result.rawText, result.definitions.isEmpty {
                    Text(raw)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.primary.opacity(0.92))
                        .lineSpacing(4)
                } else if let ai = result.aiAnalysis {
                    AIMentalModelCardView(word: result.word, aiText: ai)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.definitions) { def in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 8) {
                                    Text(def.partOfSpeech)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.12))
                                        .cornerRadius(3)

                                    Text(def.meaning)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(.primary)
                                        .textSelection(.enabled)
                                }

                                ForEach(def.exampleItems) { item in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("•")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary.opacity(0.6))

                                        Text(item.text)
                                            .font(.system(size: 12, design: .serif))
                                            .foregroundColor(.secondary)
                                            .lineSpacing(2)
                                            .textSelection(.enabled)

                                        Spacer(minLength: 6)

                                        Button(action: {
                                            AudioPlayer.shared.playSentence(text: item.text, audioURL: item.audioURL)
                                        }) {
                                            Image(systemName: item.audioURL != nil ? "speaker.wave.2.fill" : "speaker.wave.1")
                                                .font(.system(size: 10))
                                                .foregroundColor(item.audioURL != nil ? .accentColor : .secondary.opacity(0.7))
                                                .padding(3)
                                                .background(item.audioURL != nil ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                                                .clipShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .help(item.audioURL != nil ? "播放母语者原声录音" : "朗读例句 (AI神经语音)")
                                    }
                                    .padding(.leading, 12)
                                    .padding(.vertical, 1)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            result.sourceId == "ai_engine"
                ? Color.purple.opacity(0.05)
                : Color(NSColor.controlBackgroundColor).opacity(0.4)
        )
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    result.sourceId == "ai_engine"
                        ? Color.purple.opacity(0.2)
                        : Color.secondary.opacity(0.12),
                    lineWidth: 1
                )
        )
    }

    private func iconForSource(_ id: String) -> String {
        switch id {
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
