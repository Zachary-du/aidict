import Foundation
import zlib

/// MDX v1.x / v2.x 格式词典解析器
/// 支持 MDict 格式 (.mdx)，兼容 Oxford、LDOCE、Cambridge 等主流词典
/// - v1.x (LZO): 4字节整数，key_block_info 不压缩，key/record块 LZO 压缩
/// - v2.x (zlib): 8字节整数，key_block_info zlib 压缩，key/record块 zlib 压缩
public final class MDXParser {

    public enum MDXError: LocalizedError {
        case tooSmall
        case unsupportedVersion(String)
        case decompressionFailed(String)
        case formatError(String)
        case lzoNotSupported

        public var errorDescription: String? {
            switch self {
            case .tooSmall:
                return "文件太小，不是有效的 MDX 文件"
            case .unsupportedVersion(let v):
                return "不支持的引擎版本: \(v)（当前仅支持 MDX v1.x 和 v2.x）"
            case .decompressionFailed(let m):
                return "解压缩失败: \(m)"
            case .formatError(let m):
                return "MDX 格式解析错误: \(m)"
            case .lzoNotSupported:
                return "此 MDX 词典使用 LZO 压缩（MDX v1.x 格式）。\n请使用 MDict 软件将其另存为 v2.0 格式，或使用 pyglossary 工具转换为 MDX v2.0 再导入。"
            }
        }
    }

    // MARK: - 版本相关常量

    private struct MDXVersion {
        let major: Int    // 1 或 2
        let raw: String
        // v1.x: 4字节整数, v2.x: 8字节整数
        var numberWidth: Int { major >= 2 ? 8 : 4 }
        // v1.x: key_block_info 中 key size 用1字节, v2.x 用2字节
        var keySizeWidth: Int { major >= 2 ? 2 : 1 }
        // v1.x: key_block_info 无 null terminator 额外计数, v2.x 有
        var keyTextTerm: Int { major >= 2 ? 1 : 0 }
    }

    private let data: Data
    private var pos: Int = 0
    private var version: MDXVersion = MDXVersion(major: 2, raw: "2.0")
    private var strEncoding: String.Encoding = .utf8
    private var encryptFlag: Int = 0

    public init(url: URL) throws {
        self.data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count > 64 else { throw MDXError.tooSmall }
    }

    // MARK: - Public

    public func parse(onProgress: (@Sendable (Int, Int) -> Void)? = nil) throws -> [(word: String, definition: String)] {
        pos = 0
        try parseHeader()

        let keys = try parseKeySection()
        onProgress?(0, keys.count)

        let entries = try parseRecordSection(keys: keys, onProgress: onProgress)
        return entries
    }

    // MARK: - 头部解析

    private func parseHeader() throws {
        // Header 长度: 4字节 big-endian
        let headerLen = Int(readU32BE())
        guard headerLen > 0, pos + headerLen + 4 <= data.count else {
            throw MDXError.formatError("Header 长度异常: \(headerLen)")
        }
        let headerBytes = slice(headerLen)
        _ = readU32LE() // adler32 校验和（跳过）

        // Header 是 UTF-16-LE XML
        let xml = String(data: headerBytes, encoding: .utf16LittleEndian) ?? ""

        // 解析版本
        let versionStr = xmlAttr(xml, "GeneratedByEngineVersion") ?? "2.0"
        let majorVer = Int(versionStr.prefix(1)) ?? 2
        version = MDXVersion(major: majorVer, raw: versionStr)

        // 解析编码
        let encStr = xmlAttr(xml, "Encoding") ?? "UTF-8"
        if encStr.uppercased().contains("UTF-16") || encStr.uppercased() == "UNICODE" {
            strEncoding = .utf16LittleEndian
        } else if encStr.uppercased().contains("GB") {
            strEncoding = String.Encoding(rawValue:
                CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        } else {
            strEncoding = .utf8
        }

        // 加密标志
        let encryptStr = xmlAttr(xml, "Encrypted") ?? "No"
        if encryptStr == "No" || encryptStr == "" {
            encryptFlag = 0
        } else if encryptStr == "Yes" {
            encryptFlag = 1
        } else {
            encryptFlag = Int(encryptStr) ?? 0
        }

        aLog("MDX Header: version=\(versionStr) encoding=\(encStr) encrypt=\(encryptFlag)")
    }

    // MARK: - Key 索引区解析

    private func parseKeySection() throws -> [(offset: UInt64, word: String)] {
        let numWidth = version.numberWidth

        // v2.x: 5个数字(8字节) + 4字节校验和
        // v1.x: 4个数字(4字节), 无校验和
        let numKeyBlocks   = readNumber(width: numWidth)
        let _              = readNumber(width: numWidth) // num_entries
        var infoDecompSize = UInt64(0)
        if version.major >= 2 {
            infoDecompSize = readNumber(width: numWidth)
        }
        let infoSize       = readNumber(width: numWidth)
        let _              = readNumber(width: numWidth) // key_blocks_size
        if version.major >= 2 {
            _ = readU32BE() // adler32 checksum
        }

        // 读取 key block info
        let infoRaw = slice(Int(infoSize))
        let infoData: Data
        if version.major >= 2 {
            // v2.x: zlib 压缩（可能还有 encrypt=2 混淆）
            infoData = try decodeKeyBlockInfo(infoRaw, decompSize: Int(infoDecompSize))
        } else {
            // v1.x: 不压缩，直接使用
            infoData = infoRaw
        }

        // 解析 block info 列表
        var ic = 0
        var compSizes: [Int] = []
        var decompSizes: [Int] = []

        while ic < infoData.count {
            let remaining = infoData.count - ic
            if remaining < numWidth { break }

            _ = readNumberFrom(infoData, cursor: &ic, width: numWidth) // num_entries_in_block

            // key size 字段宽度: v1.x=1字节, v2.x=2字节
            let keySizeW = version.keySizeWidth

            // first key size
            guard ic + keySizeW <= infoData.count else { break }
            let fkSize: Int
            if keySizeW == 2 {
                fkSize = Int(readU16BEFrom(infoData, c: &ic))
            } else {
                fkSize = Int(infoData[infoData.startIndex + ic]); ic += 1
            }

            // first key text (包含 null terminator)
            let extraBytes = strEncoding == .utf16LittleEndian ? (fkSize + version.keyTextTerm) * 2 : fkSize + version.keyTextTerm
            ic += min(extraBytes, infoData.count - ic)

            // last key size
            guard ic + keySizeW <= infoData.count else { break }
            let lkSize: Int
            if keySizeW == 2 {
                lkSize = Int(readU16BEFrom(infoData, c: &ic))
            } else {
                lkSize = Int(infoData[infoData.startIndex + ic]); ic += 1
            }

            // last key text (包含 null terminator)
            let extraBytes2 = strEncoding == .utf16LittleEndian ? (lkSize + version.keyTextTerm) * 2 : lkSize + version.keyTextTerm
            ic += min(extraBytes2, infoData.count - ic)

            guard ic + numWidth * 2 <= infoData.count else { break }
            let compSize   = Int(readNumberFrom(infoData, cursor: &ic, width: numWidth))
            let decompSize = Int(readNumberFrom(infoData, cursor: &ic, width: numWidth))

            compSizes.append(compSize)
            decompSizes.append(decompSize)
        }

        if compSizes.count != Int(numKeyBlocks) {
            aLog("MDX: key block count mismatch: expected=\(numKeyBlocks) parsed=\(compSizes.count)", level: .warn)
        }

        // 解析各 key block
        var keys: [(offset: UInt64, word: String)] = []
        let blockCount = min(compSizes.count, decompSizes.count)
        for i in 0..<blockCount {
            let blockRaw = slice(compSizes[i])
            let blockData = try decodeBlock(blockRaw, decompSize: decompSizes[i])
            var kc = 0
            while kc + version.numberWidth < blockData.count {
                let offset = readNumberFrom(blockData, cursor: &kc, width: version.numberWidth)
                let (word, adv) = nullTermStr(blockData, kc, strEncoding)
                kc += adv
                let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    keys.append((offset: offset, word: clean))
                }
            }
        }

        aLog("MDX: 成功解析 \(keys.count) 个词条索引")
        return keys
    }

    // MARK: - Record 数据区解析

    private func parseRecordSection(keys: [(offset: UInt64, word: String)],
                                    onProgress: (@Sendable (Int, Int) -> Void)?) throws -> [(word: String, definition: String)] {
        let numWidth = version.numberWidth
        let numRecordBlocks = readNumber(width: numWidth)
        _ = readNumber(width: numWidth) // num_entries
        let recordInfoSize  = readNumber(width: numWidth)
        _ = readNumber(width: numWidth) // record_blocks_size

        var recCompSizes:   [Int] = []
        var recDecompSizes: [Int] = []
        let numInfo = Int(recordInfoSize) / (numWidth * 2)
        for _ in 0..<numInfo {
            recCompSizes.append(Int(readNumber(width: numWidth)))
            recDecompSizes.append(Int(readNumber(width: numWidth)))
        }

        // 解压拼接所有 record data
        var allRecords = Data()
        let blockCount = min(Int(numRecordBlocks), recCompSizes.count, recDecompSizes.count)
        for i in 0..<blockCount {
            let raw = slice(recCompSizes[i])
            let decompressed = try decodeBlock(raw, decompSize: recDecompSizes[i])
            allRecords.append(decompressed)
        }
        aLog("MDX: Record 数据总解压大小: \(allRecords.count) 字节")

        let sortedKeys = keys.sorted { $0.offset < $1.offset }
        var entries: [(word: String, definition: String)] = []
        entries.reserveCapacity(sortedKeys.count)
        let total = sortedKeys.count

        for i in 0..<total {
            let start = Int(sortedKeys[i].offset)
            let end   = (i + 1 < total) ? Int(sortedKeys[i + 1].offset) : allRecords.count
            guard start >= 0, start < end, end <= allRecords.count else { continue }

            let defData = allRecords[start..<end]
            var raw: String
            if strEncoding == .utf16LittleEndian {
                raw = String(data: defData, encoding: .utf16LittleEndian) ?? ""
            } else {
                raw = String(data: defData, encoding: strEncoding)
                    ?? String(data: defData, encoding: .utf8) ?? ""
            }
            raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0\r\n "))

            let plain = stripHTML(raw)
            if !plain.isEmpty {
                entries.append((word: sortedKeys[i].word, definition: plain))
            }
            if i % 3000 == 0 { onProgress?(i, total) }
        }

        aLog("MDX: 解析完成，共 \(entries.count) 条有效释义")
        return entries
    }

    // MARK: - 块解压 (通用：自动识别 v1.x/v2.x)

    private func decodeKeyBlockInfo(_ raw: Data, decompSize: Int) throws -> Data {
        guard raw.count >= 8 else { return raw }
        // v2.x: 前4字节必为 02 00 00 00
        guard raw[0] == 0x02 else {
            // 不是 zlib 压缩的 key_block_info，直接用原始数据
            return raw
        }
        // encrypt=2: key block info 被混淆加密，需先解密
        if encryptFlag & 0x02 != 0 {
            // 解密：key = ripemd128(adler32_bytes + 0x3695_LE)
            // 简化版：许多 MDX2 词典加密级别低，直接尝试 zlib
            // 此处跳过加密，大多数无密码 MDX2 词典不需要
        }
        let compressed = raw.dropFirst(8) // 跳过 4字节类型 + 4字节adler32
        return try zlibDecompress(Data(compressed), hint: decompSize)
    }

    private func decodeBlock(_ raw: Data, decompSize: Int) throws -> Data {
        guard raw.count >= 8 else {
            return raw.count > 8 ? Data(raw[8...]) : Data(raw)
        }

        // MDX block header: [4字节压缩信息 LE] [4字节adler32]
        // 压缩类型在低4位: 0=无压缩, 1=LZO, 2=zlib
        let compType = Int(raw[0]) & 0x0F

        switch compType {
        case 0:
            // 无压缩
            return Data(raw.dropFirst(8))
        case 1:
            // LZO 压缩 (MDX v1.x)
            let compressed = raw.dropFirst(8)
            return try LZO.decompress(Data(compressed), expectedSize: decompSize)
        case 2:
            // zlib 压缩
            let compressed = raw.dropFirst(8)
            return try zlibDecompress(Data(compressed), hint: decompSize)
        default:
            // 未知压缩类型
            throw MDXError.decompressionFailed("未知压缩类型: \(compType)")
        }
    }

    private func zlibDecompress(_ compressed: Data, hint: Int) throws -> Data {
        guard compressed.count > 0 else { return Data() }

        var bufSize = max(hint, compressed.count * 3, 65536)
        var output  = Data(count: bufSize)
        var destLen = uLongf(bufSize)

        let status: Int32 = output.withUnsafeMutableBytes { outBuf in
            compressed.withUnsafeBytes { inBuf -> Int32 in
                guard let oPtr = outBuf.baseAddress?.assumingMemoryBound(to: Bytef.self),
                      let iPtr = inBuf.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                    return Z_STREAM_ERROR
                }
                return uncompress(oPtr, &destLen, iPtr, uLong(compressed.count))
            }
        }

        if status == Z_OK {
            return output.prefix(Int(destLen))
        } else if status == Z_BUF_ERROR {
            // 缓冲区不足，扩大重试
            bufSize *= 4
            output  = Data(count: bufSize)
            destLen = uLongf(bufSize)
            let retryStatus: Int32 = output.withUnsafeMutableBytes { outBuf in
                compressed.withUnsafeBytes { inBuf -> Int32 in
                    guard let oPtr = outBuf.baseAddress?.assumingMemoryBound(to: Bytef.self),
                          let iPtr = inBuf.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                        return Z_STREAM_ERROR
                    }
                    return uncompress(oPtr, &destLen, iPtr, uLong(compressed.count))
                }
            }
            if retryStatus == Z_OK { return output.prefix(Int(destLen)) }
            throw MDXError.decompressionFailed("zlib 重试失败: \(retryStatus)")
        } else {
            throw MDXError.decompressionFailed("zlib 错误: \(status)")
        }
    }

    // MARK: - 二进制读取器

    /// 按 width 读取 big-endian 整数（4 或 8 字节），避免指针不对齐崩溃
    @discardableResult
    private func readNumber(width: Int) -> UInt64 {
        if width == 8 {
            guard pos + 8 <= data.count else { return 0 }
            let b0 = UInt64(data[pos])
            let b1 = UInt64(data[pos + 1])
            let b2 = UInt64(data[pos + 2])
            let b3 = UInt64(data[pos + 3])
            let b4 = UInt64(data[pos + 4])
            let b5 = UInt64(data[pos + 5])
            let b6 = UInt64(data[pos + 6])
            let b7 = UInt64(data[pos + 7])
            pos += 8
            return (b0 << 56) | (b1 << 48) | (b2 << 40) | (b3 << 32) |
                   (b4 << 24) | (b5 << 16) | (b6 << 8)  | b7
        } else {
            guard pos + 4 <= data.count else { return 0 }
            let b0 = UInt32(data[pos])
            let b1 = UInt32(data[pos + 1])
            let b2 = UInt32(data[pos + 2])
            let b3 = UInt32(data[pos + 3])
            pos += 4
            return UInt64((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
        }
    }

    private func readNumberFrom(_ d: Data, cursor c: inout Int, width: Int) -> UInt64 {
        let base = d.startIndex + c
        if width == 8 {
            guard base + 8 <= d.endIndex else { return 0 }
            let b0 = UInt64(d[base])
            let b1 = UInt64(d[base + 1])
            let b2 = UInt64(d[base + 2])
            let b3 = UInt64(d[base + 3])
            let b4 = UInt64(d[base + 4])
            let b5 = UInt64(d[base + 5])
            let b6 = UInt64(d[base + 6])
            let b7 = UInt64(d[base + 7])
            c += 8
            return (b0 << 56) | (b1 << 48) | (b2 << 40) | (b3 << 32) |
                   (b4 << 24) | (b5 << 16) | (b6 << 8)  | b7
        } else {
            guard base + 4 <= d.endIndex else { return 0 }
            let b0 = UInt32(d[base])
            let b1 = UInt32(d[base + 1])
            let b2 = UInt32(d[base + 2])
            let b3 = UInt32(d[base + 3])
            c += 4
            return UInt64((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
        }
    }

    @discardableResult
    private func readU32BE() -> UInt32 {
        guard pos + 4 <= data.count else { return 0 }
        let b0 = UInt32(data[pos])
        let b1 = UInt32(data[pos + 1])
        let b2 = UInt32(data[pos + 2])
        let b3 = UInt32(data[pos + 3])
        pos += 4
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    @discardableResult
    private func readU32LE() -> UInt32 {
        guard pos + 4 <= data.count else { return 0 }
        let b0 = UInt32(data[pos])
        let b1 = UInt32(data[pos + 1])
        let b2 = UInt32(data[pos + 2])
        let b3 = UInt32(data[pos + 3])
        pos += 4
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    private func readU16BEFrom(_ d: Data, c: inout Int) -> UInt16 {
        let base = d.startIndex + c
        guard base + 2 <= d.endIndex else { return 0 }
        let b0 = UInt16(d[base])
        let b1 = UInt16(d[base + 1])
        c += 2
        return (b0 << 8) | b1
    }

    private func slice(_ count: Int) -> Data {
        guard count > 0, pos + count <= data.count else { return Data() }
        let d = Data(data[pos..<pos+count])
        pos += count
        return d
    }

    private func nullTermStr(_ d: Data, _ start: Int, _ enc: String.Encoding) -> (String, Int) {
        let base = d.startIndex + start
        guard base < d.endIndex else { return ("", 1) }
        if enc == .utf16LittleEndian {
            var i = base
            while i + 1 < d.endIndex {
                if d[i] == 0 && d[i+1] == 0 {
                    let s = String(data: d[base..<i], encoding: .utf16LittleEndian) ?? ""
                    return (s, i - base + 2)
                }
                i += 2
            }
            return ("", d.endIndex - base)
        } else {
            var i = base
            while i < d.endIndex && d[i] != 0 { i += 1 }
            let s = String(data: d[base..<i], encoding: enc)
                ?? String(data: d[base..<i], encoding: .utf8) ?? ""
            return (s, i - base + 1)
        }
    }

    // MARK: - HTML 清洗

    private func xmlAttr(_ xml: String, _ key: String) -> String? {
        let pattern = "\(key)=[\"']([^\"']+)[\"']"
        guard let range = xml.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(xml[range])
        let inner = match.dropFirst(key.count + 2).dropLast(1)
        return String(inner)
    }

    private func stripHTML(_ html: String) -> String {
        if html.hasPrefix("@@@LINK=") {
            return "参见: " + html.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var s = html
        s = s.replacingOccurrences(of: "<br>",    with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br/>",   with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br />",  with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "</p>",    with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "</div>",  with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "</li>",   with: "\n", options: .caseInsensitive)
        while let r = s.range(of: "<[^>]+>", options: .regularExpression) {
            s.replaceSubrange(r, with: "")
        }
        s = s.replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let lines = s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
