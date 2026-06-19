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

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.claudeDir = home.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: claudeDir.path)
    }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard isEnabled else { return [] }
        let cutoff = since ?? defaultSince
        let files = enumerateJSONL(in: claudeDir)
        var results: [UsageRecord] = []
        for url in files {
            let recs = parseFile(url: url, cutoff: cutoff)
            results.append(contentsOf: recs)
        }
        return results
    }

    // MARK: - Helpers

    private func enumerateJSONL(in dir: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "jsonl" {
                files.append(url)
            }
        }
        return files
    }

    private func parseFile(url: URL, cutoff: Date) -> [UsageRecord] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        var records: [UsageRecord] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            guard let rec = mapLine(obj), rec.timestamp >= cutoff else { continue }
            records.append(rec)
        }
        return records
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
