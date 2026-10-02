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
            } else if imageService.isLoading && !word.contains(" ") {
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
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11))
                        .foregroundColor(.purple)
                    Text("认知语言学心智模型 · 空间隐喻")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.purple)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.06))
                .cornerRadius(6)
            }

            // 心智模型 Markdown 释义正文
            Text(LocalizedStringKey(aiText))
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.95))
                .lineSpacing(3.5)
                .textSelection(.enabled)

            // 快捷追问与自由问答胶囊
            if let onFollowUp = onFollowUp {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().opacity(0.4)
                    HStack(spacing: 5) {
                        Text("向 AI 追问:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        Button(action: {
                            onFollowUp("请对比【\(word)】与最容易混淆的常见近义词的核心差异与适用语境。")
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
                            onFollowUp("请为【\(word)】提供 3 个地道商务或日常会话例句，并分析用法。")
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
    }
}
