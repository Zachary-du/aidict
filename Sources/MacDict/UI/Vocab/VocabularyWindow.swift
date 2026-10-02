import SwiftUI

public struct VocabularyWindowView: View {
    @ObservedObject var store = VocabularyStore.shared
    @State private var searchText = ""
    @State private var selectedItem: VocabularyItem?
    @State private var exportMessage: String?

    private var filteredItems: [VocabularyItem] {
        if searchText.isEmpty {
            return store.items
        }
        return store.items.filter {
            $0.word.localizedCaseInsensitiveContains(searchText) ||
            $0.definition.localizedCaseInsensitiveContains(searchText) ||
            ($0.contextSentence?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 工具栏
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索生词、释义或上下文例句...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Spacer()

                // AI 批量解析
                if store.isBatchUpdatingAI {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.65)
                        Text(store.batchProgressText ?? "AI 解析中...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.purple)
                        Button("停止") {
                            store.stopBatchUpdate()
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.08))
                    .cornerRadius(6)
                } else {
                    Button(action: {
                        Task {
                            await store.batchUpdateAllWithAI(forceAll: false)
                        }
                    }) {
                        Label("AI 深度解析全部生词", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .help("使用大模型自动为生词本中尚未生成 AI 释义的所有词汇生成结构化解析")
                }

                // 导出 CSV / Anki
                Button(action: exportVocabulary) {
                    Label("导出 CSV", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)

            Divider()

            // MARK: - 词汇列表
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(store.items.isEmpty ? "生词本还是空的，查词时点击 ⭐ 即可收录" : "没有找到匹配的生词")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredItems) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(item.word)
                                            .font(.system(size: item.word.count > 30 ? 14 : 16, weight: .bold))
                                            .foregroundColor(.primary)
                                            .lineLimit(3)

                                        if let phonetic = item.phonetic {
                                            Text(phonetic)
                                                .font(.system(size: 12, design: .serif))
                                                .foregroundColor(.secondary)
                                        }

                                        // 播放发音
                                        Button(action: {
                                            AudioPlayer.shared.speak(text: item.word)
                                        }) {
                                            Image(systemName: "speaker.wave.2")
                                                .font(.system(size: 12))
                                                .foregroundColor(.accentColor)
                                        }
                                        .buttonStyle(.plain)

                                        if item.isAIDefinition {
                                            HStack(spacing: 3) {
                                                Image(systemName: "sparkles")
                                                    .font(.system(size: 9))
                                                Text("AI 释义")
                                                    .font(.system(size: 9, weight: .bold))
                                            }
                                            .foregroundColor(.purple)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.1))
                                            .cornerRadius(4)
                                        }
                                    }
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    if let app = item.sourceAppName {
                                        Text(app)
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(4)
                                        .foregroundColor(.secondary)
                                }

                                Text(item.dateAdded, style: .date)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.8))

                                // 单词独立 AI 刷新生成按钮
                                Button(action: {
                                    Task {
                                        await store.requestAIDefinition(for: item.id)
                                    }
                                }) {
                                    if store.loadingItemIds.contains(item.id) {
                                        ProgressView()
                                            .scaleEffect(0.55)
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 12))
                                            .foregroundColor(.purple)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(store.loadingItemIds.contains(item.id))
                                .help(item.isAIDefinition ? "重新生成 AI 深度释义" : "生成 AI 深度释义")

                                // 删除
                                Button(action: {
                                    store.removeItem(id: item.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text(LocalizedStringKey(item.definition))
                            .font(.system(size: 13))
                            .foregroundColor(.primary.opacity(0.9))
                            .lineSpacing(3)

                        if let ctx = item.contextSentence, !ctx.isEmpty {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "quote.opening")
                                    .font(.system(size: 9))
                                    .foregroundColor(.accentColor)
                                Text(ctx)
                                    .font(.system(size: 11, design: .serif))
                                    .foregroundColor(.secondary)
                                    .italic()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
            }

            // MARK: - 状态栏
            HStack {
                let aiCount = store.items.filter { $0.isAIDefinition }.count
                Text("共 \(store.items.count) 个生词 · \(aiCount) 个已采用 AI 解释")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if let msg = exportMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 450)
    }

    private func exportVocabulary() {
        if let url = store.exportToCSV() {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "MacDict_生词本_\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)).csv"
            panel.begin { response in
                if response == .OK, let target = panel.url {
                    try? FileManager.default.removeItem(at: target)
                    try? FileManager.default.copyItem(at: url, to: target)
                    exportMessage = "已成功导出至: \(target.lastPathComponent)"
                }
            }
        }
    }
}
