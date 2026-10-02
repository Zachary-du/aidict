import Foundation
import OSLog

/// 全局日志系统 — 同时写到 OSLog 和本地文件，方便排查崩溃
public final class AppLogger: @unchecked Sendable {
    public static let shared = AppLogger()

    private let osLog = OSLog(subsystem: "com.dylan.MacDict", category: "general")
    private var fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.dylan.MacDict.logger", qos: .utility)

    public let logFileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/MacDict", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logFileURL = dir.appendingPathComponent("macdict.log")

        // 超过 5MB 就轮转
        if let size = try? logFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 5_000_000 {
            let old = dir.appendingPathComponent("macdict.log.old")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: logFileURL, to: old)
        }

        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()

        log("========== MacDict 启动 \(Date()) ==========")
        log("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    public func log(_ message: String, level: Level = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        let entry = "[\(timestamp())] [\(level.rawValue)] \(filename):\(line) \(function) — \(message)\n"

        // OSLog
        switch level {
        case .info:  os_log("%{public}@", log: osLog, type: .info, message)
        case .warn:  os_log("%{public}@", log: osLog, type: .default, message)
        case .error: os_log("%{public}@", log: osLog, type: .error, message)
        case .fatal: os_log("%{public}@", log: osLog, type: .fault, message)
        }

        // 写文件
        queue.async { [weak self] in
            guard let data = entry.data(using: .utf8), let fh = self?.fileHandle else { return }
            fh.write(data)
        }

        // Debug 控制台
        #if DEBUG
        print(entry, terminator: "")
        #endif
    }

    public func logCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let msg = "💥 CRASH: \(exception.name.rawValue): \(exception.reason ?? "nil")\n" +
                      "Stack: \(exception.callStackSymbols.joined(separator: "\n"))"
            AppLogger.shared.log(msg, level: .fatal)
            // 强制 flush
            AppLogger.shared.fileHandle?.synchronizeFile()
        }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    public enum Level: String {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
        case fatal = "FATAL"
    }

    deinit { fileHandle?.closeFile() }
}

// 全局简写
public func aLog(_ msg: String, level: AppLogger.Level = .info, file: String = #file, function: String = #function, line: Int = #line) {
    AppLogger.shared.log(msg, level: level, file: file, function: function, line: line)
}
