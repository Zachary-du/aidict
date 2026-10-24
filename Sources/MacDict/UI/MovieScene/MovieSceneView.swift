import SwiftUI

public struct MovieSceneView: View {
    @ObservedObject var service = MovieSceneService.shared

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

                    Text("欧美经典影视剧原片截取 · 真实演员对白与环境音效")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

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
                .help("重新检索当前词条的影视原声")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

            Divider()

            // MARK: - 主内容展示区
            if service.isLoading {
                VStack(spacing: 12) {
                    ProgressView().scaleEffect(1.1)
                    Text("正在从经典影视库检索【\(service.currentWord)】的真实截取原声音频...")
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
                            RealMovieSceneCard(scene: scene, targetWord: service.currentWord)
                        }
                    }
                    .padding(18)
                }
            }

            Divider()

            // MARK: - 底栏提示
            HStack {
                Text("🎬 标志的音频均为欧美电影/美剧原片真实截取录音（真实演员发音与背景音效，绝非 AI 朗读）。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .frame(minWidth: 500, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - 单张真实影视原声卡片组件
struct RealMovieSceneCard: View {
    let scene: MovieSceneItem
    let targetWord: String
    @ObservedObject var service = MovieSceneService.shared

    private var isPlaying: Bool {
        service.currentlyPlayingClipId == scene.id
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 影视剧照截图 (如果有)
            if let poster = scene.posterURL, let url = URL(string: poster) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.black.opacity(0.15)
                    }
                }
                .frame(width: 90, height: 60)
                .cornerRadius(6)
                .clipped()
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                // 剧名、原声标签与时长
                HStack(spacing: 6) {
                    Image(systemName: "film")
                        .font(.system(size: 11))
                        .foregroundColor(scene.isRealSoundtrack ? .red : .purple)

                    Text(scene.title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if scene.isRealSoundtrack {
                        Text("🎬 电影原声")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }

                    if let ctx = scene.context, ctx.contains("时长") {
                        Text(ctx)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // 真实原声播放小喇叭按钮（点按触发，绝非自动播放）
                    Button(action: {
                        service.playMovieAudio(scene: scene)
                    }) {
                        HStack(spacing: 4) {
                            if service.isDownloadingClip && service.currentlyPlayingClipId == scene.id {
                                ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                                Text("加载中...")
                            } else {
                                Image(systemName: isPlaying ? "speaker.wave.3.fill" : (scene.isRealSoundtrack ? "play.circle.fill" : "speaker.wave.2"))
                                    .font(.system(size: 11))
                                Text(isPlaying ? "停止" : (scene.isRealSoundtrack ? "原声播放" : "台词跟读"))
                            }
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isPlaying ? Color.red.opacity(0.18) : (scene.isRealSoundtrack ? Color.red.opacity(0.08) : Color.primary.opacity(0.06)))
                        .foregroundColor(isPlaying ? .red : (scene.isRealSoundtrack ? .red : .primary.opacity(0.88)))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(isPlaying ? "停止播放" : (scene.isRealSoundtrack ? "播放该电影/美剧真实截取的演员原声" : "朗读该台词"))
                }

                // 英文原声台词（目标单词高亮）
                highlightedQuoteView(scene.quote, highlight: targetWord)
                    .font(.system(size: 13, design: .serif))
                    .lineSpacing(3)
                    .textSelection(.enabled)

                // 中文翻译 (若有)
                if !scene.translation.isEmpty {
                    Text(scene.translation)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }

                // 剧作语境（若非纯时长）
                if let ctx = scene.context, !ctx.contains("时长") && !ctx.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9.5))
                            .foregroundColor(.orange)
                            .padding(.top, 1)

                        Text("语境：\(ctx)")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary.opacity(0.85))
                    }
                }
            }
        }
        .padding(12)
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

        let tokens = quote.components(separatedBy: " ")
        var result = Text("“")
        for (i, token) in tokens.enumerated() {
            let lower = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"'()[]*"))
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
