import Foundation
import SQLite3

public final class CustomDictionaryStore: @unchecked Sendable {
    public static let shared = CustomDictionaryStore()
    
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.dylan.MacDict.customDict", qos: .userInitiated)
    
    public struct DictMeta: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let format: String
        public let entryCount: Int
        public let createdAt: String
    }
    
    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacDict", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("dictionaries.db").path
        
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            createTables()
        }
    }
    
    private func createTables() {
        let sql = """
            CREATE TABLE IF NOT EXISTS dict_meta (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                format TEXT NOT NULL,
                entry_count INTEGER DEFAULT 0,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS entries (
                dict_id TEXT NOT NULL,
                word TEXT NOT NULL,
                definition TEXT NOT NULL,
                PRIMARY KEY (dict_id, word)
            );
            CREATE INDEX IF NOT EXISTS idx_entries_word ON entries(word);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }
    
    public var dictCount: Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM dict_meta", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }
    
    public func allDictionaries() -> [DictMeta] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT id, name, format, entry_count, created_at FROM dict_meta ORDER BY created_at DESC", -1, &stmt, nil) == SQLITE_OK else { return [] }
        var result: [DictMeta] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let format = String(cString: sqlite3_column_text(stmt, 2))
            let count = Int(sqlite3_column_int(stmt, 3))
            let created = String(cString: sqlite3_column_text(stmt, 4))
            result.append(DictMeta(id: id, name: name, format: format, entryCount: count, createdAt: created))
        }
        return result
    }
    
    public func lookup(word: String) -> String? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let sql = "SELECT definition FROM entries WHERE lower(word) = lower(?) OR trim(lower(word)) = lower(?) LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, clean, -1, transient)
        sqlite3_bind_text(stmt, 2, clean, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return String(cString: sqlite3_column_text(stmt, 0))
    }

    /// 在指定词典中查询（用于独立词典源）
    public func lookupInDict(word: String, dictId: String) -> String? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let sql = "SELECT definition FROM entries WHERE dict_id = ? AND (lower(word) = lower(?) OR trim(lower(word)) = lower(?)) LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, dictId, -1, transient)
        sqlite3_bind_text(stmt, 2, clean, -1, transient)
        sqlite3_bind_text(stmt, 3, clean, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return String(cString: sqlite3_column_text(stmt, 0))
    }

    /// 根据用户输入前缀，极速检索匹配的词条（用于搜索框即时联想，利用 idx_entries_word 毫秒级返回）
    public func searchPrefix(query: String, limit: Int = 30) -> [String] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql = "SELECT DISTINCT word FROM entries WHERE word LIKE ? ORDER BY length(word), word LIMIT ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }

        let pattern = "\(clean)%"
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, pattern, -1, transient)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = sqlite3_column_text(stmt, 0) {
                results.append(String(cString: text))
            }
        }
        return results
    }

    public func deleteDictionary(id: String) {
        sqlite3_exec(db, "DELETE FROM entries WHERE dict_id = '\(id)'", nil, nil, nil)
        sqlite3_exec(db, "DELETE FROM dict_meta WHERE id = '\(id)'", nil, nil, nil)
        
        // 关键：SQLite 删除数据后默认保留空闲页（freelist）并不返还操作系统磁盘。
        // 调用 VACUUM 彻底重构数据库并向 macOS 归还所有物理磁盘空间！
        dbQueue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            sqlite3_exec(db, "VACUUM;", nil, nil, nil)
            aLog("CustomDictionaryStore: 已执行 VACUUM 回收磁盘物理空间")
        }

        // 通知引擎刷新词典源列表
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .customDictionariesChanged, object: nil)
        }
    }

    /// 主动释放空闲页并向系统归还磁盘物理空间
    public func vacuum() {
        dbQueue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            sqlite3_exec(db, "VACUUM;", nil, nil, nil)
            aLog("CustomDictionaryStore: 手动 VACUUM 完成")
        }
    }
    
    @discardableResult
    public func importFile(
        at url: URL,
        name: String,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) throws -> DictMeta {
        let ext = url.pathExtension.lowercased()
        var entries: [(word: String, definition: String)] = []
        
        if ext == "mdx" {
            onProgress?("正在解析 MDX 词典...")
            let parser = try MDXParser(url: url)
            entries = try parser.parse(onProgress: { current, total in
                if total > 0 {
                    let pct = Int((Double(current) / Double(total)) * 100)
                    onProgress?("正在提取词条: \(current)/\(total) (\(pct)%)")
                }
            })
        } else {
            let content = try String(contentsOf: url, encoding: .utf8)
            switch ext {
            case "json":
                entries = try parseJSON(content)
            case "tsv", "tab":
                entries = parseTSV(content, separator: "\t")
            case "csv":
                entries = parseTSV(content, separator: ",")
            case "txt":
                let sample = String(content.prefix(2000))
                if sample.contains("\t") {
                    entries = parseTSV(content, separator: "\t")
                } else if sample.contains(",") {
                    entries = parseTSV(content, separator: ",")
                } else {
                    throw NSError(domain: "CustomDict", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法识别的 TXT 格式，请确认是 TSV（制表符分隔）或 CSV（逗号分隔）"])
                }
            default:
                throw NSError(domain: "CustomDict", code: 2, userInfo: [NSLocalizedDescriptionKey: "不支持的文件格式: .\(ext)。支持 MDX / JSON / TSV / CSV"])
            }
        }
        
        guard !entries.isEmpty else {
            throw NSError(domain: "CustomDict", code: 3, userInfo: [NSLocalizedDescriptionKey: "词典中未解析出有效词条"])
        }
        
        let dictId = UUID().uuidString
        let now = ISO8601DateFormatter().string(from: Date())
        
        onProgress?("正在写入本地数据库 (\(entries.count) 条)...")
        
        // 高性能批量插入优化
        sqlite3_exec(db, "PRAGMA synchronous = OFF", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA journal_mode = MEMORY", nil, nil, nil)
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        
        var insertStmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO entries (dict_id, word, definition) VALUES (?, ?, ?)", -1, &insertStmt, nil)
        
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var count = 0
        for (word, def) in entries {
            let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanWord.isEmpty else { continue }
            sqlite3_bind_text(insertStmt, 1, dictId, -1, transient)
            sqlite3_bind_text(insertStmt, 2, cleanWord, -1, transient)
            sqlite3_bind_text(insertStmt, 3, def, -1, transient)
            sqlite3_step(insertStmt)
            sqlite3_reset(insertStmt)
            count += 1
            if count % 10000 == 0 {
                onProgress?("正在保存: \(count)/\(entries.count)")
            }
        }
        sqlite3_finalize(insertStmt)
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous = NORMAL", nil, nil, nil)
        
        // 记录元数据
        var metaStmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO dict_meta (id, name, format, entry_count, created_at) VALUES (?, ?, ?, ?, ?)", -1, &metaStmt, nil)
        sqlite3_bind_text(metaStmt, 1, dictId, -1, transient)
        sqlite3_bind_text(metaStmt, 2, name, -1, transient)
        sqlite3_bind_text(metaStmt, 3, ext.uppercased(), -1, transient)
        sqlite3_bind_int(metaStmt, 4, Int32(entries.count))
        sqlite3_bind_text(metaStmt, 5, now, -1, transient)
        sqlite3_step(metaStmt)
        sqlite3_finalize(metaStmt)
        
        aLog("自定义词典导入完成: \(name) (\(entries.count) 条, \(ext))")
        let meta = DictMeta(id: dictId, name: name, format: ext.uppercased(), entryCount: entries.count, createdAt: now)
        // 通知引擎刷新词典源列表
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .customDictionariesChanged, object: nil)
        }
        return meta
    }

    // MARK: - 文本解析器
    
    private func parseJSON(_ content: String) throws -> [(word: String, definition: String)] {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            throw NSError(domain: "CustomDict", code: 10, userInfo: [NSLocalizedDescriptionKey: "JSON 解析失败"])
        }
        
        var result: [(word: String, definition: String)] = []
        
        if let dict = json as? [String: String] {
            result = dict.map { ($0.key, $0.value) }
        } else if let dict = json as? [String: Any] {
            for (k, v) in dict {
                result.append((k, "\(v)"))
            }
        } else if let arr = json as? [[String: Any]] {
            for obj in arr {
                let word = obj["word"] as? String ?? obj["w"] as? String ?? ""
                let def = obj["definition"] as? String ?? obj["def"] as? String ?? obj["meaning"] as? String ?? ""
                if !word.isEmpty && !def.isEmpty {
                    result.append((word, def))
                }
            }
        }
        
        return result
    }
    
    private func parseTSV(_ content: String, separator: String) -> [(word: String, definition: String)] {
        var result: [(word: String, definition: String)] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.components(separatedBy: separator)
            guard parts.count >= 2 else { continue }
            let word = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let def = parts[1...].joined(separator: separator)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !word.isEmpty && !def.isEmpty {
                result.append((word, def))
            }
        }
        return result
    }
    
    deinit {
        sqlite3_close(db)
    }
}

// MARK: - 通知名
extension Notification.Name {
    /// 自定义词典列表发生变化（导入/删除），DictionaryEngine 监听此通知刷新 allSources
    static let customDictionariesChanged = Notification.Name("com.dylan.MacDict.customDictionariesChanged")
}
