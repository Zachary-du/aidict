import AppKit
import SwiftUI

@MainActor
public final class HUDCompanionPanel: NSPanel {
    public static let shared = HUDCompanionPanel()

    private var activeTask: Task<Void, Never>?
    private weak var currentParentPanel: NSWindow?

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false

        let hostingView = NSHostingView(rootView: HUDCompanionView())
        self.contentView = hostingView
    }

    /// 计算基于当前内容的理想高度（确定性计算，绝不触发 AppKit 约束刷新递归崩溃）
    private func calculateOptimalHeight(compW: CGFloat, isEnlarged: Bool) -> CGFloat {
        let maxImgH: CGFloat = isEnlarged ? 360 : 240
        var totalH: CGFloat = 34 // 顶栏高度与间距

        if let img = HUDCompanionViewModel.shared.image {
            let aspect = img.size.width / max(1, img.size.height)
            let interiorW = compW - 28
            let imgH = min(maxImgH, max(120, interiorW / aspect))
            totalH += imgH + 12
        }

        if let concept = HUDCompanionViewModel.shared.conceptText, !concept.isEmpty {
            // 根据深度通透理解文案长度动态分配阅读高度
            let charCount = concept.count
            let estTextH: CGFloat = charCount > 150 ? (isEnlarged ? 290 : 240) : 150
            totalH += estTextH + 36
        } else {
            totalH += 60
        }

        return totalH + 28 // 容器外边距
    }

    /// 智能动态计算伴侣卡相对主窗口的位置（优先级：右侧 -> 左侧 -> 下方 -> 上方，绝不超出屏幕）
    public func updatePosition(relativeTo parentFrame: NSRect? = nil, animated: Bool = false) {
        let parentF: NSRect
        if let p = parentFrame {
            parentF = p
        } else if let p = currentParentPanel?.frame {
            parentF = p
        } else {
            parentF = NSRect(x: 100, y: 300, width: 460, height: 520)
        }

        guard let screen = NSScreen.screens.first(where: { NSPointInRect(parentF.origin, $0.frame) }) ?? NSScreen.main else {
            return
        }
        let sf = screen.visibleFrame
        let pad: CGFloat = 8
        let isEnlarged = HUDCompanionViewModel.shared.isEnlarged
        let compW: CGFloat = isEnlarged ? 560 : 440

        // 依据当前内容测量合适高度，支持大图与详细直观文案
        let fittingH = calculateOptimalHeight(compW: compW, isEnlarged: isEnlarged)
        let compH: CGFloat = min(max(fittingH, 180), sf.height - 40)

        var targetX: CGFloat = 0
        var targetY: CGFloat = parentF.maxY - compH // 默认与主弹窗顶部对齐

        // 1. 尝试放在主弹窗右侧
        if parentF.maxX + pad + compW <= sf.maxX {
            targetX = parentF.maxX + pad
            targetY = max(sf.minY + pad, min(parentF.maxY - compH, sf.maxY - compH - pad))
        }
        // 2. 尝试放在主弹窗左侧
        else if parentF.minX - pad - compW >= sf.minX {
            targetX = parentF.minX - pad - compW
            targetY = max(sf.minY + pad, min(parentF.maxY - compH, sf.maxY - compH - pad))
        }
        // 3. 尝试放在主弹窗下方（水平居中对齐）
        else if parentF.minY - pad - compH >= sf.minY {
            targetX = max(sf.minX + pad, min(parentF.midX - compW / 2, sf.maxX - compW - pad))
            targetY = parentF.minY - pad - compH
        }
        // 4. 尝试放在主弹窗上方
        else {
            targetX = max(sf.minX + pad, min(parentF.midX - compW / 2, sf.maxX - compW - pad))
            targetY = min(sf.maxY - compH - pad, parentF.maxY + pad)
        }

        // 最终严格边界保护
        targetX = max(sf.minX + pad, min(targetX, sf.maxX - compW - pad))
        targetY = max(sf.minY + pad, min(targetY, sf.maxY - compH - pad))

        let targetRect = NSRect(x: targetX, y: targetY, width: compW, height: compH)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(targetRect, display: true)
            }
        } else {
            self.setFrame(targetRect, display: true)
        }
    }

    /// 延迟异步拉取示意图与两句直观理解，拉取成功后丝滑呈现
    public func prepareAndShowDelayed(for rawWord: String, parentPanel: HUDPanel) {
        let cleanWord = rawWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanWord.isEmpty, !cleanWord.contains(" "), cleanWord.count <= 35 else {
            dismiss()
            return
        }

        activeTask?.cancel()
        currentParentPanel = parentPanel
        HUDCompanionViewModel.shared.reset(for: cleanWord)

        activeTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            // 微小防抖延迟（0.25 秒），避免用户鼠标极速划过屏幕时闪烁创建卡片
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, parentPanel.isVisible else { return }

            // 并发异步获取插画与直观理解
            async let imageTask = WordImageService.shared.fetchImageAsync(for: cleanWord)
            async let conceptTask = IntuitiveConceptService.shared.fetchConcept(for: cleanWord)

            let (imgTuple, conceptStr) = await (imageTask, conceptTask)
            guard !Task.isCancelled, parentPanel.isVisible else { return }
            guard !HUDCompanionViewModel.shared.isDismissed else { return }

            // 若两者皆空（如断网且无缓存），静默退出，不打扰主弹窗体验
            if imgTuple.image == nil && conceptStr.isEmpty {
                return
            }

            HUDCompanionViewModel.shared.image = imgTuple.image
            HUDCompanionViewModel.shared.conceptText = conceptStr
            HUDCompanionViewModel.shared.isLoadingImage = false
            HUDCompanionViewModel.shared.isLoadingConcept = false

            // 定位并展示
            self.updatePosition(relativeTo: parentPanel.frame, animated: false)

            // 安全挂载父子窗口关联（杜绝重复或失效抛异常）
            if self.parent != parentPanel {
                if let p = self.parent {
                    p.removeChildWindow(self)
                }
                if parentPanel.isVisible {
                    parentPanel.addChildWindow(self, ordered: .above)
                }
            }

            self.alphaValue = 0
            self.orderFront(nil)

            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.animator().alphaValue = 1.0
            }
        }
    }

    private func detachAndOrderOut() {
        if let p = self.parent {
            p.removeChildWindow(self)
        } else if let cp = self.currentParentPanel, cp.childWindows?.contains(self) == true {
            cp.removeChildWindow(self)
        }
        self.currentParentPanel = nil
        self.orderOut(nil)
    }

    public func dismiss() {
        activeTask?.cancel()
        activeTask = nil

        if self.isVisible {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                self.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                DispatchQueue.main.async {
                    self?.detachAndOrderOut()
                }
            })
        } else {
            detachAndOrderOut()
        }
    }
}
