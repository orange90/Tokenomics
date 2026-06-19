import Foundation

/// Cursor 用量采集：扫描 ~/Library/Application Support/Cursor 下的本地用量缓存（usage.json / state.vscdb）。
/// 由于 Cursor 内部数据结构不公开，目前采用「文件存在性 + 后续可扩展」的策略：
///   1. 探测 cursor 配置目录
///   2. 在 storage.json 中查找 token 计数字段（best-effort）
///   3. 找不到时返回空数组，UI 提示用户在 Cursor 中导出 CSV
final class CursorCollector: UsageCollector {
    let id = "cursor"
    let displayName = "Cursor"

    private let cursorDir: URL
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.cursorDir = home.appendingPathComponent("Library/Application Support/Cursor", isDirectory: true)
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: cursorDir.path)
    }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard isEnabled else { return [] }
        // best-effort: 寻找 User/globalStorage/state.vscdb-journal 旁的 usage 文件
        let candidates = [
            cursorDir.appendingPathComponent("User/globalStorage/cursor.usage.json"),
            cursorDir.appendingPathComponent("User/usage.json")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let recs = try? parseUsageJSON(url: url) { return recs }
        }
        return []
    }

    private func parseUsageJSON(url: URL) throws -> [UsageRecord] {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        // 期望格式（猜测，多版本兼容）：
        // { "events": [ { "timestamp": ..., "model": "...", "input": N, "output": N } ] }
        guard let events = json["events"] as? [[String: Any]] else { return [] }
        return events.compactMap { e -> UsageRecord? in
            let ts = parseDate(e["timestamp"]) ?? Date()
            let model = (e["model"] as? String) ?? "auto"
            let input = (e["input"] as? Int) ?? (e["input_tokens"] as? Int) ?? 0
            let output = (e["output"] as? Int) ?? (e["output_tokens"] as? Int) ?? 0
            if input == 0 && output == 0 { return nil }
            return UsageRecord(
                timestamp: ts,
                provider: Provider.cursor.rawValue,
                model: model,
                sourceApp: "Cursor",
                inputTokens: input,
                outputTokens: output,
                requestId: e["id"] as? String
            )
        }
    }

    private func parseDate(_ raw: Any?) -> Date? {
        if let n = raw as? Double { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        if let s = raw as? String {
            return ISO8601DateFormatter().date(from: s)
        }
        return nil
    }
}
