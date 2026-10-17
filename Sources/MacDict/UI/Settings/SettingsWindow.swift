import SwiftUI

public struct SettingsWindowView: View {
    @ObservedObject var settings = SettingsStore.shared
    @State private var selectedTab = 0
    @State private var isAccessibilityGranted = AXIsProcessTrusted()

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(settings: settings, isAccessibilityGranted: $isAccessibilityGranted)
                .tabItem {
                    Label("取词与快捷键", systemImage: "keyboard")
                }
                .tag(0)

            DictionarySettingsView(settings: settings)
                .tabItem {
                    Label("词典管理", systemImage: "book.pages")
                }
                .tag(1)

            AISettingsView(settings: settings)
                .tabItem {
                    Label("AI 语境配置", systemImage: "sparkles")
                }
                .tag(2)

            AboutUpdateSettingsView(settings: settings)
                .tabItem {
                    Label("关于与更新", systemImage: "info.circle")
                }
                .tag(3)
        }
        .padding(20)
        .frame(width: 580, height: 700)
        .onAppear {
            checkPermissions()
        }
    }

    private func checkPermissions() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }
}

// MARK: - 取词与快捷键设置
struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Binding var isAccessibilityGranted: Bool

    var body: some View {
        Form {
            Section(header: Text("取词模式与开关").font(.headline)) {
                Toggle("启用悬停取词 (Hover Lookup)", isOn: $settings.isHoverLookupEnabled)
                
                if settings.isHoverLookupEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("悬停触发停顿延时:")
                            Slider(value: $settings.hoverDelay, in: 0.2...1.2, step: 0.05)
                            Text("\(String(format: "%.2f", settings.hoverDelay)) 秒")
                                .font(.system(.body, design: .monospaced))
                        }
                        Text("提示：延时过短可能在正常移动鼠标时频繁弹出，建议 0.4~0.6 秒。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 20)

                    Toggle("仅在按住 Option (⌥) 键时触发悬停 (防误触模式)", isOn: $settings.hoverRequiresOptionKey)
                        .padding(.leading, 20)
                }

                Toggle("启用选中文本后快捷键查词", isOn: $settings.isShortcutLookupEnabled)
                Toggle("查词后自动朗读发音", isOn: $settings.playAudioOnLookup)
                Toggle("查词时显示概念图示卡片", isOn: $settings.showIntuitiveCompanion)
            }

            Section(header: Text("全局默认快捷键说明").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("选中文本后快速查词:")
                        Spacer()
                        Text("⌥ D (Option + D)")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }
                    HStack {
                        Text("悬停取词模式独立开关:")
                        Spacer()
                        Text("⌥ ⌘ H (Option + Cmd + H)")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }
                    HStack {
                        Text("划词快捷键模式独立开关:")
                        Spacer()
                        Text("⌥ ⌘ S (Option + Cmd + S)")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
            }

            Section(header: Text("系统权限状态").font(.headline)) {
                HStack {
                    Image(systemName: isAccessibilityGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isAccessibilityGranted ? .green : .orange)
                    Text(isAccessibilityGranted ? "macOS 辅助功能已授权，可以精准提取屏幕文本" : "未授权辅助功能权限，屏幕取词将受限")
                    Spacer()
                    if !isAccessibilityGranted {
                        Button("去授权") {
                            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                            AXIsProcessTrustedWithOptions(options)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 词典管理设置
struct DictionarySettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var engine = DictionaryEngine.shared
    @State private var showMWKey = false
    @State private var customDicts: [CustomDictionaryStore.DictMeta] = []
    @State private var isImporting = false
    @State private var importStatus = ""

    private var orderedSources: [any DictionarySource] {
        let order = settings.sourceOrder
        return engine.allSources.sorted { a, b in
            let ai = order.firstIndex(of: a.id) ?? Int.max
            let bi = order.firstIndex(of: b.id) ?? Int.max
            return ai < bi
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── 词典源列表（可拖拽排序）──────────────────────────────
                DictSectionHeader("启用的词典源")
                Text("拖动右侧 ≡ 可调整查词顺序，左侧开关可启用/禁用。")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 8)

                List {
                    ForEach(orderedSources, id: \.id) { source in
                        DictSourceRow(
                            source: source,
                            isEnabled: settings.isSourceEnabled(source.id),
                            onToggle: { settings.toggleSource(source.id) }
                        )
                    }
                    .onMove { from, to in
                        var ids = orderedSources.map { $0.id }
                        ids.move(fromOffsets: from, toOffset: to)
                        settings.sourceOrder = ids
                    }
                }
                .listStyle(.plain)
                .frame(height: max(CGFloat(orderedSources.count) * 58, 120))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 16)

                // ── 发音与 AI 神经语音 (Neural TTS) ──────────────────────────
                DictSectionHeader("发音与 AI 神经语音 (Neural TTS)")
                PronunciationSettingsSection(settings: settings)

                // ── Merriam-Webster Key ───────────────────────────────────
                DictSectionHeader("Merriam-Webster API Key")
                VStack(alignment: .leading, spacing: 8) {
                    Text("免费注册后可获得每日 1000 次的请求额度。")
                        .font(.caption).foregroundColor(.secondary)
                    Link("在 dictionaryapi.com 获取免费 Key →",
                         destination: URL(string: "https://dictionaryapi.com/register/index")!)
                        .font(.caption)
                    HStack {
                        if showMWKey {
                            TextField("Merriam-Webster API Key:", text: $settings.merriamWebsterAPIKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Merriam-Webster API Key:", text: $settings.merriamWebsterAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(action: { showMWKey.toggle() }) {
                            Image(systemName: showMWKey ? "eye.slash" : "eye")
                        }
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 16)

                // ── 自定义本地词典 ─────────────────────────────────────────
                DictSectionHeader("自定义本地词典")
                VStack(alignment: .leading, spacing: 8) {
                    Text("支持导入 MDX (MDict v2.x) 权威词典，以及 JSON / TSV / CSV / TXT 格式。")
                        .font(.caption).foregroundColor(.secondary)

                    if !customDicts.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(customDicts) { dict in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(dict.name).font(.system(size: 13, weight: .medium))
                                        Text("\(dict.format.uppercased()) · \(dict.entryCount) 条词条")
                                            .font(.system(size: 11)).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Button(action: { deleteDict(dict) }) {
                                        Image(systemName: "trash").foregroundColor(.red)
                                    }.buttonStyle(.plain)
                                }
                                .padding(.vertical, 6).padding(.horizontal, 2)
                                Divider()
                            }
                        }
                    } else {
                        Text("尚未导入词典").font(.caption).foregroundColor(.secondary)
                    }

                    Button(action: { importDictFile() }) {
                        Label("导入词典文件…", systemImage: "plus.circle")
                    }
                    if isImporting {
                        HStack {
                            ProgressView().scaleEffect(0.7)
                            Text(importStatus).font(.caption).foregroundColor(.secondary)
                        }
                    } else if !importStatus.isEmpty {
                        Text(importStatus).font(.caption)
                            .foregroundColor(importStatus.hasPrefix("✅") ? .green : .red)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .padding(.top, 12)
        }
        .onAppear {
            customDicts = CustomDictionaryStore.shared.allDictionaries()
            DictionaryEngine.shared.refreshCustomSources()
            settings.syncSourceOrder(allSourceIds: DictionaryEngine.shared.allSources.map { $0.id })
        }
    }

    private func importDictFile() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["mdx", "json", "tsv", "csv", "txt", "tab"]
        panel.allowsMultipleSelection = false
        panel.message = "选择词典文件（支持 MDX / JSON / TSV / CSV / TXT）"
        panel.prompt = "导入"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // 文件有效性快速预检
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard fileSize > 64 else {
            let alert = NSAlert()
            alert.messageText = "无效的词典文件"
            alert.informativeText = "所选文件体积过小或无法读取，请确认文件完整有效。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "知道了")
            alert.runModal()
            return
        }

        let fileName = url.deletingPathExtension().lastPathComponent
        isImporting = true
        importStatus = "正在读取 \(fileName)…"

        Task.detached {
            do {
                let meta = try CustomDictionaryStore.shared.importFile(at: url, name: fileName) { p in
                    Task { @MainActor in importStatus = p }
                }
                await MainActor.run {
                    customDicts = CustomDictionaryStore.shared.allDictionaries()
                    isImporting = false
                    importStatus = "✅ 导入成功：\(meta.name) (\(meta.entryCount) 条)"
                    settings.syncSourceOrder(allSourceIds: DictionaryEngine.shared.allSources.map { $0.id })

                    // 弹出成功提示框
                    let alert = NSAlert()
                    alert.messageText = "词典导入成功"
                    alert.informativeText = "已成功导入「\(meta.name)」，共包含 \(meta.entryCount) 条词条！\n已自动加入上方启用的词典源列表中，您可以自由开启或拖动 ≡ 调整查词顺序。"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "好的")
                    alert.runModal()
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importStatus = "❌ 导入失败: \(error.localizedDescription)"

                    // 弹出明确错误提示框，避免直接闪退或无感退出
                    let alert = NSAlert()
                    alert.messageText = "词典解析或导入失败"
                    alert.informativeText = "\(error.localizedDescription)\n\n若为特殊加密或不规则格式，建议确认文件完整性或使用 MDict Desktop 重新另存。"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "我知道了")
                    alert.runModal()
                }
            }
        }
    }

    private func deleteDict(_ dict: CustomDictionaryStore.DictMeta) {
        // 从 sourceOrder 中移除该词典的 source ID
        let sourceId = "custom_dict_\(dict.id)"
        settings.sourceOrder.removeAll { $0 == sourceId }
        settings.enabledSources.remove(sourceId)
        // 删除词典数据（会触发 customDictionariesChanged 通知）
        CustomDictionaryStore.shared.deleteDictionary(id: dict.id)
        customDicts = CustomDictionaryStore.shared.allDictionaries()
        importStatus = ""
    }
}

// MARK: - 发音与 AI 神经语音设置组件
private struct PronunciationSettingsSection: View {
    @ObservedObject var settings: SettingsStore
    @State private var isPlayingSample: Bool = false
    @State private var cacheSizeText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. 默认口音
            VStack(alignment: .leading, spacing: 6) {
                Text("默认发音口音:")
                    .font(.system(size: 12, weight: .medium))
                Picker("", selection: $settings.preferredAccent) {
                    Text("🇺🇸 美式英语 (en-US)").tag("us")
                    Text("🇬🇧 英式英语 (en-GB)").tag("uk")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }

            Divider()

            // 2. 语音合成引擎
            VStack(alignment: .leading, spacing: 6) {
                Text("发音与 TTS 引擎:")
                    .font(.system(size: 12, weight: .medium))
                Picker("", selection: $settings.ttsEngine) {
                    Text("✨ AI 神经高拟真 (超自然 · 推荐)").tag("neural")
                    Text("🤖 OpenAI TTS (需配置 Key)").tag("openai")
                    Text("🖥️ macOS 系统本地语音").tag("system")
                }
                .pickerStyle(.radioGroup)

                if settings.ttsEngine == "neural" {
                    Text("优先播放词典真人原声；长句或生僻词自动调用现代神经网络高保真模型，语调自然生动，彻底告别机械音。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if settings.ttsEngine == "openai" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("使用 OpenAI 的 tts-1 神经网络语音模型（复用 AI 设置中的 API Key）。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Text("音色选择:")
                                .font(.caption)
                            Picker("", selection: $settings.openaiTTSVoice) {
                                Text("Alloy (自然中性)").tag("alloy")
                                Text("Nova (生动女声)").tag("nova")
                                Text("Echo (浑厚男声)").tag("echo")
                                Text("Fable (英伦叙事)").tag("fable")
                                Text("Onyx (深沉磁性)").tag("onyx")
                                Text("Shimmer (清亮女声)").tag("shimmer")
                            }
                            .frame(width: 170)
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                } else {
                    Text("提示：可在 Mac「系统设置」->「辅助功能」->「朗读内容」中下载免费的 Siri 高清自然语音包（如 Stephanie / Ava / Oliver）以提升系统音质。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // 3. 试听与缓存管理
            HStack {
                Button(action: playSample) {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2.fill")
                        Text(isPlayingSample ? "正在发音..." : "试听发音效果")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                if !cacheSizeText.isEmpty {
                    Text("音频缓存: \(cacheSizeText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("清理缓存") {
                    AITTSManager.shared.clearAudioCache()
                    updateCacheSize()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 16)
        .onAppear {
            updateCacheSize()
        }
    }

    private func playSample() {
        isPlayingSample = true
        let sample = "Resources and capabilities define our potential."
        AudioPlayer.shared.speak(text: sample, accent: settings.preferredAccent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            isPlayingSample = false
            updateCacheSize()
        }
    }

    private func updateCacheSize() {
        let bytes = AITTSManager.shared.cacheSizeInBytes
        if bytes == 0 {
            cacheSizeText = "0 KB"
        } else if bytes < 1024 * 1024 {
            cacheSizeText = "\(bytes / 1024) KB"
        } else {
            cacheSizeText = String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

// MARK: - DictionarySettingsView 辅助组件

private struct DictSectionHeader: View {
    let title: String
    init(_ t: String) { title = t }
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }
}

private struct DictSourceRow: View {
    let source: any DictionarySource
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: source.icon)
                .font(.system(size: 14))
                .foregroundColor(isEnabled ? .accentColor : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(source.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isEnabled ? .primary : .secondary)
                    // 自定义词典加个小标签
                    if source.id.hasPrefix("custom_dict_") {
                        Text("自定义")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.purple.opacity(0.7))
                            .cornerRadius(3)
                    }
                }
                Text(sourceDescription(source))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(get: { isEnabled }, set: { _ in onToggle() }))
                .toggleStyle(.switch)
                .labelsHidden()

            // 拖拽把手
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13))
                .foregroundColor(Color.secondary.opacity(0.5))
                .frame(width: 22)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func sourceDescription(_ source: any DictionarySource) -> String {
        // 自定义词典：直接从 SingleCustomDictionarySource 读取词条数
        if let custom = source as? SingleCustomDictionarySource {
            return "\(custom.dictFormat) 格式 · \(custom.entryCount) 条词条"
        }
        switch source.id {
        case "system_oxford":      return "macOS 内置牛津词典，完全离线，秒出结果"
        case "free_dictionary_api":return "Free Dictionary API — 英英释义，含美/英发音"
        case "wiktionary":         return "Wiktionary — 多词性释义，无需 Key，全球 CDN"
        case "merriam_webster":    return "Merriam-Webster — 权威美式词典，含音标（需 Key）"
        case "ai_engine":          return "AI 语境解析 — 结合上下文深度剖析，简明扼要"
        default:                   return ""
        }
    }
}

// MARK: - AI 语境大模型配置
struct AISettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var showKey = false

    private let defaultSystemPrompt = "你是一位精通英语的语言学专家。请用简洁清晰的中文解析词汇，重点突出语境含义，避免废话冗长。回复控制在200字以内。"
    private let defaultUserPromptHint = """
    支持占位符：{word}（查询词）、{context}（上下文句子）
    留空使用内置精简提示词（词性音标、核心释义、例句与语境翻译）。
    """

    var body: some View {
        Form {
            Section(header: Text("AI 大模型服务配置").font(.headline)) {
                Text("支持 OpenAI、DeepSeek、Gemini 等兼容格式接口。")
                    .font(.caption).foregroundColor(.secondary)

                TextField("API 地址 (Endpoint):", text: $settings.aiEndpoint)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if showKey {
                        TextField("API Key:", text: $settings.aiApiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key:", text: $settings.aiApiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { showKey.toggle() }) {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                }

                TextField("模型名称 (Model):", text: $settings.aiModel)
                    .textFieldStyle(.roundedBorder)
            }

            Section(header: Text("AI 系统提示词 (System Prompt)").font(.headline)) {
                Text("定义 AI 的角色定位与排版风格。默认配置为工整纯文本自然排版，不输出任何 Markdown 格式标记。可直接在下方自由修改：")
                    .font(.caption).foregroundColor(.secondary)

                TextEditor(text: $settings.aiSystemPrompt)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 85, maxHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                HStack {
                    Text("💡 提示：修改后自动保存生效；如需还原可随时重置。")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("恢复默认系统提示词") {
                        settings.resetSystemPrompt()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            Section(header: Text("AI 用户查词提示词模板 (User Prompt)").font(.headline)) {
                Text("中英查词时发送给 AI 的指令模板，支持 {word}（查询词）与 {context}（语境句子）占位符。已预置中英双向解析逻辑，可随时修改：")
                    .font(.caption).foregroundColor(.secondary)

                TextEditor(text: $settings.aiUserPromptTemplate)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minHeight: 120, maxHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                HStack {
                    Text("💡 提示：输入词汇会自动替换 {word}；划词语境会自动注入 {context}。")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("恢复默认模板") {
                        settings.resetUserPrompt()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            Section(header: Text("推荐端点").font(.headline)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Gemini:   https://generativelanguage.googleapis.com/v1beta/openai/chat/completions  (gemini-2.0-flash)")
                    Text("• DeepSeek: https://api.deepseek.com/v1/chat/completions  (deepseek-chat)")
                    Text("• OpenAI:   https://api.openai.com/v1/chat/completions  (gpt-4o-mini)")
                    Text("• Ollama:   http://localhost:11434/v1/chat/completions  (qwen2.5)")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 关于与自动更新设置
struct AboutUpdateSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var updateManager = UpdateManager.shared

    var body: some View {
        VStack(spacing: 16) {
            // 应用基本信息展示
            VStack(spacing: 8) {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                } else {
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                }

                Text("MacDict 词典")
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                HStack(spacing: 8) {
                    Text("版本 v\(UpdateManager.currentVersion) (Build \(UpdateManager.buildNumber))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("Apple Silicon 原生")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)
                }

                Text("原生轻量、极速常驻的 macOS 划词/查词与 AI 助理工具")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 10)

            Divider()

            // 自动更新配置与检查卡片
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("软件更新")
                            .font(.system(size: 13, weight: .semibold))
                        Text(updateManager.statusMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        Task {
                            await updateManager.checkForUpdates(silent: false)
                        }
                    }) {
                        HStack(spacing: 4) {
                            if updateManager.isChecking {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                            }
                            Text(updateManager.isChecking ? "检查中..." : "检查更新")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(updateManager.isChecking)
                }

                Toggle("启动应用时自动检查最新版本", isOn: $settings.autoCheckUpdates)
                    .font(.system(size: 12))

                // 若发现新版本，展示更新亮点与一键升级卡片
                if updateManager.hasNewVersion {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.orange)
                            Text("发现新版本 v\(updateManager.latestVersion)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                        }

                        if !updateManager.releaseNotes.isEmpty {
                            ScrollView {
                                Text(updateManager.releaseNotes)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                            }
                            .frame(maxHeight: 100)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(6)
                        }

                        HStack(spacing: 10) {
                            Button(action: {
                                updateManager.downloadLatestDMG()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text(updateManager.isDownloading ? "正在下载安装包..." : "一键下载并打开安装包 (DMG)")
                                }
                                .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(updateManager.isDownloading)

                            if let pageURL = updateManager.releasePageURL {
                                Button(action: {
                                    NSWorkspace.shared.open(pageURL)
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "safari")
                                        Text("前往 GitHub 查看")
                                    }
                                    .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))

            // 开源与许可信息
            HStack {
                Button(action: {
                    if let url = URL(string: UpdateManager.repoURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text("GitHub 开源仓库 (Zachary-du/aidict)")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("MIT License · 免费开源")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 4)

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
