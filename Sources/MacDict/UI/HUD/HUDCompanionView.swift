import AppKit
import SwiftUI

@MainActor
public final class HUDCompanionViewModel: ObservableObject {
    public static let shared = HUDCompanionViewModel()

    @Published public var word: String = ""
    @Published public var image: NSImage? = nil
    @Published public var conceptText: String? = nil
    @Published public var isLoadingImage: Bool = false
    @Published public var isLoadingConcept: Bool = false
    @Published public var isDismissed: Bool = false
    @Published public var isEnlarged: Bool = false

    private init() {}

    public func reset(for queryWord: String) {
        self.word = queryWord
        self.image = WordImageService.shared.getCachedImage(for: queryWord)
        self.conceptText = IntuitiveConceptService.shared.resolveImmediateConcept(for: queryWord)
        self.isLoadingImage = (self.image == nil)
        self.isLoadingConcept = false
        self.isDismissed = false
        self.isEnlarged = false
    }

    public func toggleEnlarged() {
        self.isEnlarged.toggle()
        HUDCompanionPanel.shared.updatePosition(animated: true)
    }

    public func dismiss() {
        self.isDismissed = true
        HUDCompanionPanel.shared.dismiss()
    }
}

/// 伴随式概念图示视图（极简、原生、高画质）
public struct HUDCompanionView: View {
    @ObservedObject var viewModel = HUDCompanionViewModel.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶栏：标题、缩放与关闭
            HStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Text("概念图示")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: {
                    viewModel.toggleEnlarged()
                }) {
                    Image(systemName: viewModel.isEnlarged ? "minus.magnifyingglass" : "plus.magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help(viewModel.isEnlarged ? "还原标准尺寸" : "放大显示")

                Button(action: {
                    viewModel.dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }

            // 图示展示区
            if let img = viewModel.image {
                Image(nsImage: img)
                    .interpolation(.high)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: viewModel.isEnlarged ? 360 : 240)
                    .background(Color.primary.opacity(0.02))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.toggleEnlarged()
                    }
                    .help(viewModel.isEnlarged ? "点击还原标准尺寸" : "点击放大显示")
            } else if viewModel.isLoadingImage {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                    Text("正在载入图示...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: 36)
                .padding(.horizontal, 10)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(6)
            }

            // 直观脑海意象与底层通透理解（核心画面 + 具象感知 + 灵魂本义与场景贯通）
            if let concept = viewModel.conceptText, !concept.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.accentColor)
                        Text("底层通透理解")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        Text(LocalizedStringKey(concept))
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(.primary.opacity(0.92))
                            .lineSpacing(4.5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                    .frame(maxHeight: viewModel.isEnlarged ? 340 : 240)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                )
            } else if viewModel.isLoadingConcept {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                    Text("正在解析意象...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: 28)
                .padding(.horizontal, 10)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 3)
    }
}
