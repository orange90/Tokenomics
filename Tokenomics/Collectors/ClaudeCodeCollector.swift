import Foundation

/// Claude Code CLI 用量采集：解析 ~/.claude/projects/**/*.jsonl 中的 message.usage 字段。
///
/// 文件格式（每行一个 JSON 对象，典型 schema）：
/// {
///   "type": "assistant",
///   "timestamp": "2025-12-01T08:23:45.123Z",
///   "message": {
///     "id": "msg_xxx",
///     "model": "claude-sonnet-4-20250514",
///     "usage": {
///       "input_tokens": 1234,
///       "output_tokens": 567,
///       "cache_creation_input_tokens": 0,
///       "cache_read_input_tokens": 0
///     }
///   },
///   "requestId": "req_xxx"
/// }
final class ClaudeCodeCollector: UsageCollector {
    let id = "claude-code"
    let displayName = "Claude Code"

    private let claudeDir: URL
    /// path -> (mtime epoch, parsed size). 在 collect 前由 Scheduler 注入，
    /// collect 后由 Scheduler 持久化到 CollectorState.cursorPayload。
    private var cursor: [String: FileCursor] = [:]

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.claudeDir = home.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: claudeDir.path)
    }

    var cursorPayload: String? {
        get { FileCursor.encode(cursor) }
        set { cursor = FileCursor.decode(newValue) }
    }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard isEnabled else { return [] }
        let cutoff = since ?? defaultSince
        let candidates = enumerateJSONL(in: claudeDir, cutoff: cutoff)
        var results: [UsageRecord] = []
        var nextCursor: [String: FileCursor] = [:]
        for entry in candidates {
            let key = entry.url.path
            let prev = cursor[key]

            // 短路 1：mtime 完全不变 → 文件没有任何新行，沿用旧 cursor，跳过 IO。
            if let prev, prev.mtime == entry.mtime, prev.size == entry.size {
                nextCursor[key] = prev
                continue
            }

            // 短路 2：mtime/size 变了，但旧 size 仍在新 size 内 → 只读增量字节。
            let parsed = parseFile(
                url: entry.url,
                cutoff: cutoff,
                startOffset: (prev.map { Int64($0.size) }).flatMap { $0 <= entry.size ? $0 : nil } ?? 0
            )
            results.append(contentsOf: parsed)
            nextCursor[key] = FileCursor(mtime: entry.mtime, size: entry.size)
        }
        cursor = nextCursor
        return results
    }

    // MARK: - Helpers

    /// 一次 enumerate 同时拿到 mtime / size，避免后续再做 stat。
    /// 过滤掉 mtime < cutoff 的文件（30 天前未改动的 jsonl 没有新数据可读）。
    private struct FileEntry {
        let url: URL
        let mtime: TimeInterval
        let size: Int64
    }

    private func enumerateJSONL(in dir: URL, cutoff: Date) -> [FileEntry] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [FileEntry] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: keys)
            let mtime = values?.contentModificationDate
            if let mtime, mtime < cutoff { continue }
            let size = Int64(values?.fileSize ?? 0)
            files.append(FileEntry(
                url: url,
                mtime: mtime?.timeIntervalSince1970 ?? 0,
                size: size
            ))
        }
        return files
    }

    /// 用 FileHandle 流式读取，避免一次性把整个 jsonl 装进内存。
    /// startOffset > 0 时只读增量；为容错 startOffset 不是行边界的情况，
    /// 会丢弃首个不完整片段（无 newline 结尾的数据）。
    private func parseFile(url: URL, cutoff: Date, startOffset: Int64) -> [UsageRecord] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        if startOffset > 0 {
            do { try handle.seek(toOffset: UInt64(startOffset)) } catch { return [] }
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }

        var records: [UsageRecord] = []
        let skipFirstFragment = startOffset > 0
        var index = 0
        var lineStart = 0
        let bytes = [UInt8](data)
        let newline: UInt8 = 0x0A
        while index < bytes.count {
            if bytes[index] == newline {
                if !(skipFirstFragment && lineStart == 0) {
                    if let rec = parseLine(bytes: bytes, start: lineStart, end: index, cutoff: cutoff) {
                        records.append(rec)
                    }
                }
                lineStart = index + 1
            }
            index += 1
        }
        // 文件末尾可能没有换行符。只有当我们读到的是全文件（startOffset == 0）
        // 或之前已经至少跳过一个片段时，最后一段才是完整行。
        if lineStart < bytes.count {
            let isCompleteLine = !(skipFirstFragment && lineStart == 0)
            if isCompleteLine,
               let rec = parseLine(bytes: bytes, start: lineStart, end: bytes.count, cutoff: cutoff) {
                records.append(rec)
            }
        }
        return records
    }

    private func parseLine(bytes: [UInt8], start: Int, end: Int, cutoff: Date) -> UsageRecord? {
        guard end > start else { return nil }
        let slice = Data(bytes[start..<end])
        guard let obj = try? JSONSerialization.jsonObject(with: slice) as? [String: Any],
              let rec = mapLine(obj),
              rec.timestamp >= cutoff else { return nil }
        return rec
    }

    private func mapLine(_ obj: [String: Any]) -> UsageRecord? {
        // type 必须为 assistant（用户消息没有 usage）
        let type = obj["type"] as? String
        guard type == "assistant" || type == nil else { return nil }

        let timestamp = parseTimestamp(obj["timestamp"])
        let requestId = obj["requestId"] as? String ?? (obj["id"] as? String)

        guard let message = obj["message"] as? [String: Any] else { return nil }
        let model = (message["model"] as? String) ?? "unknown"
        let normalizedModel = normalizeClaudeModel(model)
        guard let usage = message["usage"] as? [String: Any] else { return nil }

        let input = (usage["input_tokens"] as? Int) ?? 0
        let output = (usage["output_tokens"] as? Int) ?? 0
        let cw = (usage["cache_creation_input_tokens"] as? Int) ?? 0
        let cr = (usage["cache_read_input_tokens"] as? Int) ?? 0

        if input == 0 && output == 0 && cw == 0 && cr == 0 { return nil }

        return UsageRecord(
            timestamp: timestamp,
            provider: Provider.anthropic.rawValue,
            model: normalizedModel,
            sourceApp: "Claude Code",
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cw,
            cacheReadTokens: cr,
            requestId: requestId
        )
    }

    private func parseTimestamp(_ raw: Any?) -> Date {
        if let s = raw as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            let f2 = ISO8601DateFormatter()
            if let d = f2.date(from: s) { return d }
        }
        if let n = raw as? Double { return Date(timeIntervalSince1970: n) }
        return Date()
    }

    /// 把 "claude-sonnet-4-5-20251022" / "anthropic/claude-sonnet-4-5" → "claude-sonnet-4-5"
    private func normalizeClaudeModel(_ raw: String) -> String {
        let lower = raw.lowercased()
        // 注意：必须按"更具体的前缀"在前的顺序匹配，
        // 否则 "claude-opus-4-5-..." 会被先命中的 "claude-opus-4" 截断。
        let knownPrefixes = [
            "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", "claude-opus-4-5", "claude-opus-4-1", "claude-opus-4",
            "claude-sonnet-4-8", "claude-sonnet-4-7", "claude-sonnet-4-6", "claude-sonnet-4-5", "claude-sonnet-4",
            "claude-haiku-4-8", "claude-haiku-4-7", "claude-haiku-4-6", "claude-haiku-4-5", "claude-haiku-4",
            "claude-fable-5", "claude-mythos-5", "claude-mythos-preview",
            "claude-3-7-sonnet", "claude-3-7-haiku",
            "claude-3-5-sonnet", "claude-3-5-haiku",
            "claude-3-opus", "claude-3-sonnet", "claude-3-haiku"
        ]
        // 使用 contains 而非 hasPrefix，兼容 "anthropic/claude-..." 等带前缀的写法。
        for p in knownPrefixes where lower.contains(p) { return p }
        return raw
    }
}
