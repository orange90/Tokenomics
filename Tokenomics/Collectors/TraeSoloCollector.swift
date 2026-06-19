import Foundation

/// TRAE Solo 用量采集：扫描 ~/Library/Application Support/Trae 下的 usage 日志文件。
/// 实际目录结构可能为 ~/.trae-cn 或类似，多路径兼容。
final class TraeSoloCollector: UsageCollector {
    let id = "trae-solo"
    let displayName = "TRAE Solo"

    private let candidateDirs: [URL]

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.candidateDirs = [
            home.appendingPathComponent("Library/Application Support/Trae", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/TRAE", isDirectory: true),
            home.appendingPathComponent(".trae", isDirectory: true),
            home.appendingPathComponent(".trae-cn", isDirectory: true)
        ]
    }

    var isEnabled: Bool {
        candidateDirs.contains(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    func collect(since: Date?) async throws -> [UsageRecord] {
        let cutoff = since ?? defaultSince
        var records: [UsageRecord] = []
        for dir in candidateDirs where FileManager.default.fileExists(atPath: dir.path) {
            records.append(contentsOf: scan(dir: dir, cutoff: cutoff))
        }
        return records
    }

    private func scan(dir: URL, cutoff: Date) -> [UsageRecord] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var results: [UsageRecord] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent.lowercased()
            guard name.contains("usage") || name.contains("token") || name.hasSuffix(".jsonl") else { continue }
            results.append(contentsOf: parseFile(url: url, cutoff: cutoff))
        }
        return results
    }

    private func parseFile(url: URL, cutoff: Date) -> [UsageRecord] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        var records: [UsageRecord] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            let ts = parseTimestamp(obj["timestamp"] ?? obj["time"] ?? obj["created_at"])
            guard ts >= cutoff else { continue }
            let model = (obj["model"] as? String) ?? "auto"
            let input = (obj["input_tokens"] as? Int) ?? (obj["promptTokens"] as? Int) ?? 0
            let output = (obj["output_tokens"] as? Int) ?? (obj["completionTokens"] as? Int) ?? 0
            if input == 0 && output == 0 { continue }
            records.append(UsageRecord(
                timestamp: ts,
                provider: Provider.traeSolo.rawValue,
                model: model,
                sourceApp: "TRAE Solo",
                inputTokens: input,
                outputTokens: output,
                requestId: obj["id"] as? String ?? obj["requestId"] as? String
            ))
        }
        return records
    }

    private func parseTimestamp(_ raw: Any?) -> Date {
        if let s = raw as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            if let d = ISO8601DateFormatter().date(from: s) { return d }
        }
        if let n = raw as? Double { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        return Date()
    }
}
