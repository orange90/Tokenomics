import Foundation

/// Qoder 用量采集：扫描 ~/Library/Application Support/Qoder 下的本地日志。
final class QoderCollector: UsageCollector {
    let id = "qoder"
    let displayName = "Qoder"

    private let qoderDir: URL
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.qoderDir = home.appendingPathComponent("Library/Application Support/Qoder", isDirectory: true)
    }

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: qoderDir.path)
    }

    func collect(since: Date?) async throws -> [UsageRecord] {
        guard isEnabled else { return [] }
        let cutoff = since ?? defaultSince
        guard let enumerator = FileManager.default.enumerator(
            at: qoderDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var records: [UsageRecord] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent.lowercased()
            guard name.hasSuffix(".jsonl") || name.contains("usage") else { continue }
            records.append(contentsOf: parseFile(url: url, cutoff: cutoff))
        }
        return records
    }

    private func parseFile(url: URL, cutoff: Date) -> [UsageRecord] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        var records: [UsageRecord] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            let ts = parseDate(obj["timestamp"] ?? obj["time"]) ?? Date()
            guard ts >= cutoff else { continue }
            let input = (obj["input_tokens"] as? Int) ?? (obj["prompt_tokens"] as? Int) ?? 0
            let output = (obj["output_tokens"] as? Int) ?? (obj["completion_tokens"] as? Int) ?? 0
            if input == 0 && output == 0 { continue }
            records.append(UsageRecord(
                timestamp: ts,
                provider: Provider.qoder.rawValue,
                model: (obj["model"] as? String) ?? "auto",
                sourceApp: "Qoder",
                inputTokens: input,
                outputTokens: output,
                requestId: obj["id"] as? String
            ))
        }
        return records
    }

    private func parseDate(_ raw: Any?) -> Date? {
        if let n = raw as? Double { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        if let s = raw as? String { return ISO8601DateFormatter().date(from: s) }
        return nil
    }
}
