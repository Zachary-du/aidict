import Foundation
import CoreGraphics
import CoreImage

public final class OCRPreprocessor: @unchecked Sendable {
    public static let shared = OCRPreprocessor()
    private let ciContext = CIContext(options: [CIContextOption.useSoftwareRenderer: false])

    private init() {}

    /// 对抓取的屏幕切片进行自适应预处理 (尤其是针对 iTerm2/终端的深色背景反相与对比度增强)
    public func preprocess(cgImage: CGImage) -> CGImage {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 4 && height > 4 else { return cgImage }

        let isDark = isDarkBackground(cgImage: cgImage)
        let ciImage = CIImage(cgImage: cgImage)

        var output = ciImage

        // 1. 如果是终端等黑底白字环境，反转为白底黑字 (Vision 神经网络在白底黑字下字形识别率提升 40%+)
        if isDark {
            if let invertFilter = CIFilter(name: "CIColorInvert") {
                invertFilter.setValue(output, forKey: kCIInputImageKey)
                if let inv = invertFilter.outputImage {
                    output = inv
                }
            }
        }

        // 2. 对比度与清晰度增强，消除小字号等宽字体的灰度抗锯齿杂色
        if let controlFilter = CIFilter(name: "CIColorControls") {
            controlFilter.setValue(output, forKey: kCIInputImageKey)
            controlFilter.setValue(1.25, forKey: kCIInputContrastKey)
            controlFilter.setValue(0.0, forKey: kCIInputSaturationKey) // 转为纯灰度，过滤终端彩色高亮干扰
            if let controlled = controlFilter.outputImage {
                output = controlled
            }
        }

        if let sharpFilter = CIFilter(name: "CISharpenLuminance") {
            sharpFilter.setValue(output, forKey: kCIInputImageKey)
            sharpFilter.setValue(0.4, forKey: kCIInputSharpnessKey)
            if let sharpened = sharpFilter.outputImage {
                output = sharpened
            }
        }

        if let finalCG = ciContext.createCGImage(output, from: output.extent) {
            return finalCG
        }

        return cgImage
    }

    /// 检测切片四个角的平均背景亮度以判断是否为深色背景
    private func isDarkBackground(cgImage: CGImage) -> Bool {
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return true
        }

        let bpp = cgImage.bitsPerPixel / 8
        let bpr = cgImage.bytesPerRow
        guard bpp >= 3 else { return true }

        let w = cgImage.width
        let h = cgImage.height

        // 采样四个角落的背景像素
        let samples = [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]
        var totalLum: Float = 0

        for (x, y) in samples {
            let offset = y * bpr + x * bpp
            let r = Float(ptr[offset])
            let g = Float(ptr[offset + 1])
            let b = Float(ptr[offset + 2])
            // 标准人眼感知亮度公式
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            totalLum += lum
        }

        let avgLum = totalLum / Float(samples.count)
        return avgLum < 128.0
    }
}
