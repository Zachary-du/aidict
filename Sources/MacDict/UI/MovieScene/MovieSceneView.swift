import SwiftUI

public struct MovieSceneView: View {
    @ObservedObject var service = MovieSceneService.shared
    @ObservedObject var audioPlayer = AudioPlayer.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 顶栏
            HStack(spacing: 12) {
                Image(systemName: "film.stack.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("影视原声名场面")
                            .font(.system(size: 14, weight: .bold))

                        if !service.currentWord.isEmpty {
                            Text("· \(service.currentWord)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.accentColor)
                        }
                    }

                    Text("欧美经典影视剧真实台词与地道语境")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 语速切换胶囊 (1.0x / 0.85x 慢读)
                Button(action: {
                    service.playbackSpeed = service.playbackSpeed == 1.0 ? 0.85 : 1.0
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "gauge.medium")
                            .font(.system(size: 10))
                        Text(service.playbackSpeed == 1.0 ? "1.0x 原速" : "0.85x 慢读")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("切换例句朗读语速")

                // 刷新按钮
                Button(action: {
                    if !service.currentWord.isEmpty {
                        service.fetchScenes(for: service.currentWord, forceRefresh: true)
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(service.isLoading)
                .help("重新生成当前词条的影视台词")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

            Divider()

            // MARK: - 主内容展示区
            if service.isLoading {
                VStack(spacing: 12) {
                    ProgressView().scaleEffect(1.1)
                    Text("正在从经典欧美影视库检索【\(service.currentWord)】的台词名场面...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.scenes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(service.errorMessage ?? "暂未检索到该词的影视原声台词")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    Button(action: {
                        if !service.currentWord.isEmpty {
                            service.fetchScenes(for: service.currentWord, forceRefresh: true)
                        }
                    }) {
                        Text("重试检索")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 14) {
                        ForEach(service.scenes) { scene in
                            MovieSceneCard(scene: scene, targetWord: service.currentWord)
                        }
                    }
                    .padding(18)
                }
            }

            Divider()

            // MARK: - 底栏提示
            HStack {
                Text("💡 点击每张卡片右侧的小喇叭即可跟读原声音频，感受地道母语者会话语境。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .frame(minWidth: 460, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - 单张影视台词卡片组件
struct MovieSceneCard: View {
    let scene: MovieSceneItem
    let targetWord: String
    @ObservedObject var audioPlayer = AudioPlayer.shared

    private var isPlaying: Bool {
        audioPlayer.currentlyPlayingText == scene.quote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 剧目抬头与角色
            HStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.system(size: 12))
                    .foregroundColor(.purple)

                Text(scene.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                if let ep = scene.seasonEpisode, !ep.isEmpty {
                    Text(ep)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                }

                if let ch = scene.character, !ch.isEmpty {
                    Text("🎭 \(ch)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 原声朗读小喇叭按钮（点按触发，绝不默认自动播放）
                Button(action: {
                    if isPlaying {
                        audioPlayer.stop()
                    } else {
                        audioPlayer.playSentence(text: scene.quote)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                            .font(.system(size: 10))
                        Text(isPlaying ? "停止" : "原声跟读")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isPlaying ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                    .foregroundColor(isPlaying ? .accentColor : .primary.opacity(0.9))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "停止朗读" : "朗读该台词原声 (AI神经语音)")
            }

            // 英文原声台词（目标单词高亮）
            highlightedQuoteView(scene.quote, highlight: targetWord)
                .font(.system(size: 13, design: .serif))
                .lineSpacing(3.5)
                .textSelection(.enabled)

            // 中文翻译
            Text(scene.translation)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(2.5)
                .textSelection(.enabled)

            // 剧作语境解读
            if let ctx = scene.context, !ctx.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(.amberColor)
                        .padding(.top, 1)

                    Text("语境：\(ctx)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.9))
                        .lineSpacing(2)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func highlightedQuoteView(_ quote: String, highlight: String) -> Text {
        let cleanHighlight = highlight.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanHighlight.isEmpty, quote.lowercased().contains(cleanHighlight) else {
            return Text("“\(quote)”")
        }

        // 简易单词高亮拼接
        let tokens = quote.components(separatedBy: " ")
        var result = Text("“")
        for (i, token) in tokens.enumerated() {
            let lower = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()[]"))
            if lower == cleanHighlight || lower.contains(cleanHighlight) {
                result = result + Text(token).bold().foregroundColor(.accentColor)
            } else {
                result = result + Text(token).foregroundColor(.primary)
            }
            if i < tokens.count - 1 {
                result = result + Text(" ")
            }
        }
        result = result + Text("”")
        return result
    }
}

extension Color {
    static let amberColor = Color(red: 0.92, green: 0.65, blue: 0.15)
}
