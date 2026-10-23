import AppKit
import SwiftUI

/// AI 核心画面与心智模型卡片组件（图文并茂，支持 Pixabay 矢量插画与 Wikipedia 免 Key 图库）
public struct AIMentalModelCardView: View {
    public let word: String
    public let aiText: String
    public var onFollowUp: ((String?) -> Void)? = nil

    @ObservedObject var imageService = WordImageService.shared

    public init(word: String, aiText: String, onFollowUp: ((String?) -> Void)? = nil) {
        self.word = word
        self.aiText = aiText
        self.onFollowUp = onFollowUp
    }

    private var isChineseWord: Bool {
        word.range(of: "\\p{Han}", options: .regularExpression) != nil
    }

    private var activeImage: NSImage? {
        let cleanWord = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if imageService.currentWord == cleanWord, let img = imageService.currentImage {
            return img
        }
        return imageService.getCachedImage(for: cleanWord)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶层图文聚合横幅（若有插画或正在检索）
            if let image = activeImage {
                HStack(alignment: .top, spacing: 12) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 160, maxHeight: 110)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.purple)
                            Text("概念意象插画")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.purple)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(4)

                        Text("以具象物理画面锚定认知，建立母语者直觉反应")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(3)

                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
                .background(Color.purple.opacity(0.04))
                .cornerRadius(10)
            } else if imageService.isLoading && !word.contains(" ") && !isChineseWord {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                    Text("正在检索匹配的矢量概念图解...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
            } else if !word.contains(" ") {
                HStack(spacing: 6) {
                    Image(systemName: isChineseWord ? "sparkles" : "brain.head.profile")
                        .font(.system(size: 11))
                        .foregroundColor(.purple)
                    Text(isChineseWord ? "AI 中译英 · 地道表达与语境辨析" : "认知语言学心智模型 · 空间隐喻")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.purple)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.06))
                .cornerRadius(6)
            }

            // 心智模型 Markdown 释义正文（支持单句独立小喇叭发音）
            AIMarkdownView(aiText, baseFontSize: 12, textColor: .primary.opacity(0.95))

            // 快捷追问与自由问答胶囊
            if let onFollowUp = onFollowUp {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().opacity(0.4)
                    HStack(spacing: 5) {
                        Text("向 AI 追问:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        Button(action: {
                            let prompt = isChineseWord
                                ? "请给出【\(word)】在不同口语与职场语境下最地道的英文表达及词义差异对比。"
                                : "请对比【\(word)】与最容易混淆的常见近义词的核心差异与适用语境。"
                            onFollowUp(prompt)
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "lightbulb")
                                Text(isChineseWord ? "地道表达" : "近义辨析")
                            }
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            let prompt = isChineseWord
                                ? "请为【\(word)】的英文翻译提供 3 个地道商务或日常会话例句，并分析用法。"
                                : "请为【\(word)】提供 3 个地道商务或日常会话例句，并分析用法。"
                            onFollowUp(prompt)
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "pencil.and.outline")
                                Text(isChineseWord ? "场景例句" : "场景造句")
                            }
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            MovieSceneWindowController.shared.show(word: word)
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "film.stack")
                                Text("影视台词")
                            }
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.08))
                            .foregroundColor(.purple)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .help("在独立弹窗中查看该词的经典影视原声名场面例句")

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
    }
}
