import SwiftUI
import AppKit

public struct AIChatView: View {
    @ObservedObject var chatService = AIChatService.shared
    @ObservedObject var settings = SettingsStore.shared
    @State private var inputText: String = ""
    @State private var copiedMessageId: UUID? = nil
    @FocusState private var isInputFocused: Bool

    public init() {}

    private var currentTopic: String {
        chatService.currentWord.isEmpty ? "英语语言助手" : chatService.currentWord
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 顶部讨论主题栏
            topicHeaderView

            Divider()

            // MARK: - 对话主消息流
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        // 初始引导与联想胶囊推荐
                        associationChipsSection

                        ForEach(chatService.messages) { msg in
                            chatMessageRow(msg)
                                .id(msg.id)
                        }

                        // 生成中动画状态
                        if chatService.isGenerating {
                            generatingIndicatorRow
                                .id("generating_indicator")
                        }

                        // 错误提示条
                        if let err = chatService.errorMessage {
                            errorBannerView(err)
                                .id("error_banner")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: chatService.messages.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: chatService.isGenerating) { isGen in
                    if isGen {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }

            Divider()

            // MARK: - 底部输入栏
            bottomInputBar
        }
        .frame(minWidth: 480, minHeight: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            isInputFocused = true
        }
    }

    // MARK: - 顶部主题 Banner
    private var topicHeaderView: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sparkles.bubble.fill")
                .font(.system(size: 18))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("AI 智能问答对话")
                        .font(.system(size: 13, weight: .bold))
                    if !chatService.currentWord.isEmpty {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(chatService.currentWord)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                }

                if let ctx = chatService.contextSentence, !ctx.isEmpty {
                    Text("语境: \"\(ctx)\"")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("当前使用模型: \(settings.aiModel.isEmpty ? "默认 AI" : settings.aiModel)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !chatService.messages.isEmpty {
                Button(action: {
                    chatService.clearMessages()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("清空对话")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("清空当前对话历史")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - 快捷联想启发胶囊 (Prompt Chips)
    private var associationChipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chatService.messages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("👋 您好！想了解关于【\(currentTopic)】的哪些方面？")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("点击下方快捷联想胶囊，或在底栏直接向 AI 提出任何发散问题：")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)
            }

            // 胶囊列表
            FlowLayout(spacing: 8) {
                chipButton(icon: "lightbulb.fill", title: "近义词与精细辨析") {
                    chatService.sendMessage("请详细列举与【\(currentTopic)】最密切的 3~4 个近义词/同义词，并清晰对比它们在语感、适用场合与感情色彩上的核心区别。")
                }

                chipButton(icon: "doc.text.fill", title: "地道造句与场景") {
                    chatService.sendMessage("请为【\(currentTopic)】提供 3 个不同地道真实场景的例句（如商务沟通、学术论文、日常口语），并附上中文释义与用法精讲。")
                }

                chipButton(icon: "link", title: "高频固定搭配") {
                    chatService.sendMessage("请总结【\(currentTopic)】在英语中最经典、最地道的动词/介词/形容词固定搭配，并给出使用示例。")
                }

                chipButton(icon: "exclamationmark.triangle.fill", title: "易混淆词与语法陷阱") {
                    chatService.sendMessage("使用【\(currentTopic)】时有哪些最容易踩坑的语法或用词误区？有哪些极其容易混淆的形近词？")
                }

                chipButton(icon: "brain.head.profile", title: "词根词缀与记忆法") {
                    chatService.sendMessage("请拆解【\(currentTopic)】的词根与词缀渊源，并分享一套生动深刻的联想记忆方法。")
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }

    private func chipButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor))
            .foregroundColor(.primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 消息行渲染
    @ViewBuilder
    private func chatMessageRow(_ msg: AIChatMessage) -> some View {
        if msg.role == "user" {
            // 用户消息（右侧）
            HStack {
                Spacer(minLength: 40)
                Text(msg.content)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .cornerRadius(14)
            }
        } else {
            // AI 助手消息（左侧卡片）
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text(msg.content)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .foregroundColor(.primary)

                    // 底部实用工具按键
                    HStack(spacing: 12) {
                        // 复制按键
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(msg.content, forType: .string)
                            copiedMessageId = msg.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                if copiedMessageId == msg.id { copiedMessageId = nil }
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: copiedMessageId == msg.id ? "checkmark" : "doc.on.doc")
                                Text(copiedMessageId == msg.id ? "已复制" : "复制")
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)

                        // 朗读按键 (调用全新升级的 AI 神经 TTS)
                        Button(action: {
                            AudioPlayer.shared.speak(text: msg.content)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "speaker.wave.2")
                                Text("朗读内容")
                            }
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)

                        // 如果是最后一条，展示重新生成
                        if msg.id == chatService.messages.last?.id && !chatService.isGenerating {
                            Button(action: {
                                chatService.regenerateLastMessage()
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("重新生成")
                                }
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )

                Spacer(minLength: 20)
            }
        }
    }

    // MARK: - 生成中状态条
    private var generatingIndicatorRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("AI 正在思考并组织解答...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Button("停止生成") {
                chatService.stopGeneration()
            }
            .font(.system(size: 11))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }

    // MARK: - 错误状态横幅
    private func errorBannerView(_ error: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.red)
            Spacer()
            Button("重试") {
                chatService.regenerateLastMessage()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.red.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - 底部输入栏
    private var bottomInputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("输入你想向 AI 提问的问题或发散联想...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .font(.system(size: 13))
                .focused($isInputFocused)
                .onSubmit {
                    sendCurrentInput()
                }

            if chatService.isGenerating {
                Button(action: {
                    chatService.stopGeneration()
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("停止当前生成")
            } else {
                Button(action: sendCurrentInput) {
                    Image(systemName: inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          ? "arrow.up.circle"
                          : "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                         ? .secondary.opacity(0.4)
                                         : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("发送提问 (Return)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func sendCurrentInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chatService.isGenerating else { return }
        inputText = ""
        chatService.sendMessage(text)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if chatService.isGenerating {
                proxy.scrollTo("generating_indicator", anchor: .bottom)
            } else if let last = chatService.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - 自动折行 FlowLayout 辅助组件
public struct FlowLayout: Layout {
    public var spacing: CGFloat = 8

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: width, height: currentY + lineHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
