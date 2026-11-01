import AppKit
import SwiftUI

/// 原生 AppKit 驱动的双击选词与可交互文本视图（基于 NSTextView）
/// 严格限制在 MacDict 词典内部使用，支持自然多行排版、段落间距、Markdown 加粗与代码字体
/// 用户双击任意单词时，AppKit 自动完成精确选词，并立即无缝触发本应用内该词的查询与跳转
public class DoubleClickableTextView: NSTextView {
    public var onDoubleClickWord: ((String) -> Void)?

    public override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager, let textContainer = textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(used.height))
    }

    public override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.size.width
        super.setFrameSize(newSize)
        if abs(newSize.width - oldWidth) > 0.5 {
            invalidateIntrinsicContentSize()
        }
    }

    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if event.clickCount == 2 {
            let range = self.selectedRange()
            if range.location != NSNotFound && range.length > 0 {
                let raw = (self.string as NSString).substring(with: range)
                if let word = DoubleClickMonitor.cleanLookupWord(raw) {
                    aLog("🎯 [SelectableTextView] 双击选词命中: '\(word)'")
                    DoubleClickMonitor.shared.recordLookup(word: word)
                    if let cb = onDoubleClickWord {
                        cb(word)
                    } else {
                        MainWindowController.shared.lookupFromDoubleClick(word)
                    }
                }
            }
        }
    }
}

/// SwiftUI 封装的富文本原生可交互组件
public struct SelectableTextView: NSViewRepresentable {
    public let markdown: String
    public var fontSize: CGFloat = 13
    public var weight: NSFont.Weight = .regular
    public var textColor: NSColor = .textColor
    public var lineSpacing: CGFloat = 3.5
    public var isSerif: Bool = false
    public var isMonospaced: Bool = false
    public var onDoubleClickWord: ((String) -> Void)? = nil

    public init(
        markdown: String,
        fontSize: CGFloat = 13,
        weight: NSFont.Weight = .regular,
        textColor: NSColor = .textColor,
        lineSpacing: CGFloat = 3.5,
        isSerif: Bool = false,
        isMonospaced: Bool = false,
        onDoubleClickWord: ((String) -> Void)? = nil
    ) {
        self.markdown = markdown
        self.fontSize = fontSize
        self.weight = weight
        self.textColor = textColor
        self.lineSpacing = lineSpacing
        self.isSerif = isSerif
        self.isMonospaced = isMonospaced
        self.onDoubleClickWord = onDoubleClickWord
    }

    public init(
        markdown: String,
        fontSize: CGFloat = 13,
        weight: NSFont.Weight = .regular,
        textColor: Color,
        lineSpacing: CGFloat = 3.5,
        isSerif: Bool = false,
        isMonospaced: Bool = false,
        onDoubleClickWord: ((String) -> Void)? = nil
    ) {
        self.init(
            markdown: markdown,
            fontSize: fontSize,
            weight: weight,
            textColor: NSColor(textColor),
            lineSpacing: lineSpacing,
            isSerif: isSerif,
            isMonospaced: isMonospaced,
            onDoubleClickWord: onDoubleClickWord
        )
    }

    public func makeNSView(context: Context) -> DoubleClickableTextView {
        let tv = DoubleClickableTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.autoresizingMask = [.width]
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    public func updateNSView(_ tv: DoubleClickableTextView, context: Context) {
        tv.onDoubleClickWord = onDoubleClickWord

        let baseFont: NSFont
        if isMonospaced {
            baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        } else if isSerif {
            let desc = NSFont.systemFont(ofSize: fontSize, weight: weight).fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: fontSize, weight: weight).fontDescriptor
            baseFont = NSFont(descriptor: desc, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: weight)
        } else {
            baseFont = NSFont.systemFont(ofSize: fontSize, weight: weight)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing

        let nsAttr: NSMutableAttributedString
        if let attr = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            nsAttr = NSMutableAttributedString(attr)
            let fullRange = NSRange(location: 0, length: nsAttr.length)

            nsAttr.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
                if let oldFont = value as? NSFont {
                    let isBold = oldFont.fontDescriptor.symbolicTraits.contains(.bold)
                    let newWeight: NSFont.Weight = isBold ? .bold : weight
                    let newFont: NSFont
                    if isMonospaced {
                        newFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: newWeight)
                    } else if isSerif {
                        let desc = NSFont.systemFont(ofSize: fontSize, weight: newWeight).fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: fontSize, weight: newWeight).fontDescriptor
                        newFont = NSFont(descriptor: desc, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: newWeight)
                    } else {
                        newFont = NSFont.systemFont(ofSize: fontSize, weight: newWeight)
                    }
                    nsAttr.addAttribute(.font, value: newFont, range: range)
                } else {
                    nsAttr.addAttribute(.font, value: baseFont, range: range)
                }
            }
            nsAttr.addAttribute(.foregroundColor, value: textColor, range: fullRange)
            nsAttr.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        } else {
            nsAttr = NSMutableAttributedString(string: markdown, attributes: [
                .font: baseFont,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ])
        }

        if tv.attributedString() != nsAttr {
            tv.textStorage?.setAttributedString(nsAttr)
            tv.invalidateIntrinsicContentSize()
        }
    }
}
