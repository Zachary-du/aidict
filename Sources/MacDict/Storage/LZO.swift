import Foundation

/// LZO1X-1 解压缩引擎 (Pure Swift 实现)
/// 参考标准 Linux kernel lib/lzo/lzo1x_decompress_safe.c (Markus F.X.J. Oberhumer)
/// 用于解压 MDX v1.x (LZO) 格式词典的 Key Blocks 与 Record Blocks
public enum LZO {

    public enum LZOError: LocalizedError {
        case inputOverrun
        case outputOverrun
        case lookbehindOverrun
        case corruptData(String)

        public var errorDescription: String? {
            switch self {
            case .inputOverrun:
                return "LZO 解压错误: 输入数据提前结束 (Input Overrun)"
            case .outputOverrun:
                return "LZO 解压错误: 输出缓冲区溢出 (Output Overrun)"
            case .lookbehindOverrun:
                return "LZO 解压错误: 历史回溯越界 (Lookbehind Overrun)"
            case .corruptData(let msg):
                return "LZO 解压错误: \(msg)"
            }
        }
    }

    /// 解压缩 LZO1X 数据流
    /// - Parameters:
    ///   - compressed: 压缩字节数据
    ///   - expectedSize: 解压后预期字节大小
    /// - Returns: 解压后的完整数据
    public static func decompress(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard !compressed.isEmpty else { return Data() }
        let inLen = compressed.count
        guard inLen >= 3 else { throw LZOError.inputOverrun }

        var output = Data(count: max(expectedSize, 65536))
        var actualLen = 0

        try output.withUnsafeMutableBytes { outBuf in
            try compressed.withUnsafeBytes { inBuf in
                guard let inPtr = inBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let outPtr = outBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    throw LZOError.corruptData("内存地址无效")
                }

                let inEnd = inPtr + inLen
                let outEnd = outPtr + outBuf.count

                var ip = inPtr
                var op = outPtr
                var t: Int = 0
                var next: Int = 0
                var state: Int = 0
                var mPos: UnsafeMutablePointer<UInt8> = outPtr

                // 检查 bitstream_version
                let bitstreamVersion: UInt8
                if inLen >= 5 && ip.pointee == 17 {
                    bitstreamVersion = ip.advanced(by: 1).pointee
                    ip += 2
                } else {
                    bitstreamVersion = 0
                }

                if ip.pointee > 17 {
                    t = Int(ip.pointee) - 17
                    ip += 1
                    if t < 4 {
                        next = t
                        state = next
                        t = next
                        if ip + t + 3 > inEnd || op + t > outEnd { throw LZOError.inputOverrun }
                        while t > 0 {
                            op.pointee = ip.pointee
                            op += 1; ip += 1
                            t -= 1
                        }
                    } else {
                        if op + t > outEnd || ip + t > inEnd { throw LZOError.outputOverrun }
                        while t > 0 {
                            op.pointee = ip.pointee
                            op += 1; ip += 1
                            t -= 1
                        }
                        state = 4
                    }
                }

                mainLoop: while true {
                    if ip >= inEnd { break mainLoop }
                    t = Int(ip.pointee)
                    ip += 1

                    if t < 16 {
                        if state == 0 {
                            if t == 0 {
                                while ip < inEnd && ip.pointee == 0 {
                                    ip += 1
                                    t += 255
                                }
                                if ip >= inEnd { throw LZOError.inputOverrun }
                                t += 15 + Int(ip.pointee)
                                ip += 1
                            }
                            t += 3
                            if op + t > outEnd || ip + t > inEnd { throw LZOError.outputOverrun }
                            while t > 0 {
                                op.pointee = ip.pointee
                                op += 1; ip += 1
                                t -= 1
                            }
                            state = 4
                            continue mainLoop
                        } else if state != 4 {
                            next = t & 3
                            mPos = op - 1 - (t >> 2)
                            if ip >= inEnd { throw LZOError.inputOverrun }
                            mPos -= Int(ip.pointee) << 2
                            ip += 1
                            if mPos < outPtr { throw LZOError.lookbehindOverrun }
                            if op + 2 > outEnd { throw LZOError.outputOverrun }
                            op.pointee = mPos.pointee; op += 1
                            op.pointee = mPos.advanced(by: 1).pointee; op += 1
                            state = next
                            t = next
                            if ip + t > inEnd || op + t > outEnd { throw LZOError.inputOverrun }
                            while t > 0 {
                                op.pointee = ip.pointee
                                op += 1; ip += 1
                                t -= 1
                            }
                            continue mainLoop
                        } else {
                            next = t & 3
                            mPos = op - (1 + 0x0800) - (t >> 2)
                            if ip >= inEnd { throw LZOError.inputOverrun }
                            mPos -= Int(ip.pointee) << 2
                            ip += 1
                            t = 3
                        }
                    } else if t >= 64 {
                        next = t & 3
                        mPos = op - 1 - ((t >> 2) & 7)
                        if ip >= inEnd { throw LZOError.inputOverrun }
                        mPos -= Int(ip.pointee) << 3
                        ip += 1
                        t = (t >> 5) - 1 + 2
                    } else if t >= 32 {
                        t = (t & 31) + 2
                        if t == 2 {
                            while ip < inEnd && ip.pointee == 0 {
                                ip += 1
                                t += 255
                            }
                            if ip >= inEnd { throw LZOError.inputOverrun }
                            t += 31 + Int(ip.pointee)
                            ip += 1
                        }
                        if ip + 2 > inEnd { throw LZOError.inputOverrun }
                        let v = Int(ip.pointee) | (Int(ip.advanced(by: 1).pointee) << 8)
                        ip += 2
                        mPos = op - 1 - (v >> 2)
                        next = v & 3
                    } else {
                        if ip + 2 > inEnd { throw LZOError.inputOverrun }
                        let v = Int(ip.pointee) | (Int(ip.advanced(by: 1).pointee) << 8)
                        if (v & 0xfffc) == 0xfffc && (t & 0xf8) == 0x18 && bitstreamVersion != 0 {
                            if ip + 3 > inEnd { throw LZOError.inputOverrun }
                            t = (t & 7) | (Int(ip.advanced(by: 2).pointee) << 3) + 4
                            if op + t > outEnd { throw LZOError.outputOverrun }
                            for _ in 0..<t { op.pointee = 0; op += 1 }
                            next = v & 3
                            ip += 3
                            state = next
                            t = next
                            if ip + t > inEnd || op + t > outEnd { throw LZOError.inputOverrun }
                            while t > 0 {
                                op.pointee = ip.pointee
                                op += 1; ip += 1
                                t -= 1
                            }
                            continue mainLoop
                        } else {
                            mPos = op - ((t & 8) << 11)
                            t = (t & 7) + 2
                            if t == 2 {
                                while ip < inEnd && ip.pointee == 0 {
                                    ip += 1
                                    t += 255
                                }
                                if ip >= inEnd { throw LZOError.inputOverrun }
                                t += 7 + Int(ip.pointee)
                                ip += 1
                            }
                            if ip + 2 > inEnd { throw LZOError.inputOverrun }
                            let v2 = Int(ip.pointee) | (Int(ip.advanced(by: 1).pointee) << 8)
                            ip += 2
                            mPos -= (v2 >> 2)
                            next = v2 & 3
                            if mPos == op {
                                break mainLoop
                            }
                            mPos -= 0x4000
                        }
                    }

                    if mPos < outPtr { throw LZOError.lookbehindOverrun }
                    if op + t > outEnd { throw LZOError.outputOverrun }

                    for _ in 0..<t {
                        op.pointee = mPos.pointee
                        op += 1; mPos += 1
                    }

                    state = next
                    t = next
                    if ip + t > inEnd || op + t > outEnd { throw LZOError.inputOverrun }
                    while t > 0 {
                        op.pointee = ip.pointee
                        op += 1; ip += 1
                        t -= 1
                    }
                }

                actualLen = op - outPtr
            }
        }

        return output.prefix(actualLen)
    }
}
