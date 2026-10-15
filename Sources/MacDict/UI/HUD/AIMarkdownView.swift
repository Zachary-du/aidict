import SwiftUI

/// 专门用于优雅渲染 AI 输出的高性能、轻量级原生 Markdown 视图
/// 完美支持各级标题 (###)、多层级列表 (* / 1.)、引用块 (>)、代码块 (```)、粗体 (**)、行内代码 (`) 与分割线
public struct AIMarkdownView: View {
    public let text: String
    public var baseFontSize: CGFloat = 12
    public var textColor: Color = .primary.opacity(0.92)

    public init(_ text: String, baseFontSize: CGFloat = 12, textColor: Color = .primary.opacity(0.92)) {
        self.text = text
        self.baseFontSize = baseFontSize
        self.textColor = textColor
    }

    public var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks) { block in
                renderBlock(block.kind)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func renderBlock(_ kind: MarkdownBlockKind) -> some View {
        switch kind {
        case .heading(let level, let content):
            formattedText(content)
                .font(.system(size: headingSize(level), weight: .bold))
                .foregroundColor(.primary)
                .padding(.top, headingTopPadding(level))
                .padding(.bottom, 1)

        case .bulletItem(let content, let indent):
            HStack(alignment: .top, spacing: 6) {
                Text(indent == 0 ? "•" : "◦")
                    .font(.system(size: baseFontSize, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.85))
                    .frame(width: 8, alignment: .trailing)
                    .padding(.top, 1)

                formattedText(content)
                    .font(.system(size: baseFontSize))
                    .lineSpacing(3.5)
                    .foregroundColor(textColor)
            }
            .padding(.leading, CGFloat(indent) * 12)

        case .numberedItem(let number, let content, let indent):
            HStack(alignment: .top, spacing: 6) {
                Text("\(number).")
                    .font(.system(size: baseFontSize - 0.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.9))
                    .frame(minWidth: 16, alignment: .trailing)
                    .padding(.top, 1)

                formattedText(content)
                    .font(.system(size: baseFontSize))
                    .lineSpacing(3.5)
                    .foregroundColor(textColor)
            }
            .padding(.leading, CGFloat(indent) * 12)

        case .quote(let content):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.65))
                    .frame(width: 3)

                formattedText(content)
                    .font(.system(size: baseFontSize - 0.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)

        case .codeBlock(let code, let lang):
            VStack(alignment: .leading, spacing: 4) {
                if let l = lang, !l.isEmpty {
                    HStack {
                        Text(l.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                Text(code)
                    .font(.system(size: baseFontSize - 1, design: .monospaced))
                    .lineSpacing(2)
                    .foregroundColor(.primary.opacity(0.95))
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
            )

        case .divider:
            Divider().opacity(0.5).padding(.vertical, 2)

        case .paragraph(let content):
            formattedText(content)
                .font(.system(size: baseFontSize))
                .lineSpacing(3.5)
                .foregroundColor(textColor)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return baseFontSize + 3.5
        case 2: return baseFontSize + 2.0
        case 3: return baseFontSize + 1.0
        default: return baseFontSize + 0.5
        }
    }

    private func headingTopPadding(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 8
        case 2: return 6
        case 3: return 4
        default: return 2
        }
    }

    private func formattedText(_ str: String) -> Text {
        if let attr = try? AttributedString(markdown: str, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        } else {
            return Text(LocalizedStringKey(str))
        }
    }
}

public struct MarkdownBlock: Identifiable {
    public let id: Int
    public let kind: MarkdownBlockKind
}

public enum MarkdownBlockKind {
    case heading(level: Int, content: String)
    case bulletItem(content: String, indent: Int)
    case numberedItem(number: String, content: String, indent: Int)
    case quote(content: String)
    case codeBlock(code: String, language: String?)
    case divider
    case paragraph(content: String)
}

public struct MarkdownParser {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var nextId = 0
        let lines = text.components(separatedBy: .newlines)

        var inCodeBlock = false
        var codeLang: String? = nil
        var codeLines: [String] = []

        var currentParagraphLines: [String] = []

        func addBlock(_ kind: MarkdownBlockKind) {
            blocks.append(MarkdownBlock(id: nextId, kind: kind))
            nextId += 1
        }

        func flushParagraph() {
            if !currentParagraphLines.isEmpty {
                let para = currentParagraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !para.isEmpty {
                    addBlock(.paragraph(content: para))
                }
                currentParagraphLines.removeAll()
            }
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            // 代码块状态切换
            if trimmed.hasPrefix("```") {
                flushParagraph()
                if inCodeBlock {
                    let code = codeLines.joined(separator: "\n")
                    addBlock(.codeBlock(code: code, language: codeLang))
                    codeLines.removeAll()
                    codeLang = nil
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLang = lang.isEmpty ? nil : lang
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            // 空行：段落分隔
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // 分割线
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                addBlock(.divider)
                continue
            }

            // 标题匹配：# ~ ######
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" })
                if hashes.count <= 6 {
                    let afterHash = trimmed.dropFirst(hashes.count)
                    if afterHash.hasPrefix(" ") {
                        flushParagraph()
                        let headingContent = afterHash.trimmingCharacters(in: .whitespaces)
                        addBlock(.heading(level: hashes.count, content: headingContent))
                        continue
                    }
                }
            }

            // 引用块：>
            if trimmed.hasPrefix(">") {
                flushParagraph()
                let quoteContent = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                addBlock(.quote(content: quoteContent))
                continue
            }

            // 列表项缩进计算
            let leadingSpaces = rawLine.prefix(while: { $0 == " " || $0 == "\t" })
            let indent = leadingSpaces.count / 2

            // 无序列表：* / - / + / •
            if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("+ ") || trimmed.hasPrefix("• ") {
                flushParagraph()
                let itemContent = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                addBlock(.bulletItem(content: itemContent, indent: indent))
                continue
            }

            // 有序列表：数字.
            if let dotIdx = trimmed.firstIndex(of: ".") {
                let prefix = trimmed[..<dotIdx]
                if let _ = Int(prefix) {
                    let afterDot = trimmed[trimmed.index(after: dotIdx)...]
                    if afterDot.hasPrefix(" ") {
                        flushParagraph()
                        let itemContent = afterDot.trimmingCharacters(in: .whitespaces)
                        addBlock(.numberedItem(number: String(prefix), content: itemContent, indent: indent))
                        continue
                    }
                }
            }

            // 普通段落行，累积
            currentParagraphLines.append(trimmed)
        }

        flushParagraph()

        if inCodeBlock && !codeLines.isEmpty {
            let code = codeLines.joined(separator: "\n")
            addBlock(.codeBlock(code: code, language: codeLang))
        }

        return blocks
    }
}
