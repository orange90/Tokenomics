import Foundation

/// OpenAI 用量采集：
/// 1) 优先解析 Codex CLI / Codex Desktop 的本地会话缓存
///    路径：~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
///    每行 JSON，关键事件为 type=="event_msg" 且 payload.type=="token_count"，
///    其中 payload.info.last_token_usage 是「本轮增量」用量；
///    模型从同文件 type=="turn_context" 行的 payload.model 获取（如 "gpt-5.5"）。
///    注意：必须用 last_token_usage，不要用 total_token_usage（累计值会重复加）。
/// 2) 若配置了 admin key，再调用 /v1/organization/usage/completions 补充组织维度的数据。
final class OpenAIAPICollector: UsageCollector {
    let id = "openai-api"
    let displayName = "OpenAI"

    private let keychain: KeychainService
    private let codexDir: URL

    init(keychain: KeychainService) {
        self.keychain = keychain
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.codexDir = home.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    /// 只要本地有 codex 缓存目录，或配置了 API Key，就视为可用。
    var isEnabled: Bool {
        if FileManager.default.fileExists(atPath: codexDir.path) { return true }
        return keychain.hasKey(KeychainKey.openai)
    }

    func collect(since: Date?) async throws -> [UsageRecord] {
        let cutoff = since ?? defaultSince
        var results: [UsageRecord] = []

        if FileManager.default.fileExists(atPath: codexDir.path) {
            let files = enumerateJSONL(in: codexDir, cutoff: cutoff)
            for url in files {
                results.append(contentsOf: parseFile(url: url, cutoff: cutoff))
            }
        }

        if let key = keychain.get(KeychainKey.openai), !key.isEmpty {
            if let apiRecords = try? await fetchFromAPI(key: key, since: cutoff) {
                results.append(contentsOf: apiRecords)
            }
        }

        return results
    }

    // MARK: - Local Codex parsing

    private func enumerateJSONL(in dir: URL, cutoff: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "jsonl" else { continue }
            if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let mtime = values.contentModificationDate,
               mtime < cutoff {
                continue
            }
            files.append(url)
        }
        return files
    }

    private func parseFile(url: URL, cutoff: Date) -> [UsageRecord] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let sessionId = extractSessionId(from: url.lastPathComponent)
        var currentModel: String = "gpt-5.5"
        var records: [UsageRecord] = []
        var eventIndex = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = obj["type"] as? String
            let payload = obj["payload"] as? [String: Any]

            if type == "turn_context", let model = payload?["model"] as? String, !model.isEmpty {
                currentModel = model
                continue
            }
            if type == "session_meta", let model = (payload?["payload"] as? [String: Any])?["model"] as? String, !model.isEmpty {
                currentModel = model
                continue
            }

            guard type == "event_msg",
                  let payload = payload,
                  (payload["type"] as? String) == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any] else { continue }

            let input = (last["input_tokens"] as? Int) ?? 0
            let output = (last["output_tokens"] as? Int) ?? 0
            let cachedInput = (last["cached_input_tokens"] as? Int) ?? 0
            let reasoning = (last["reasoning_output_tokens"] as? Int) ?? 0

            if input == 0 && output == 0 && cachedInput == 0 { continue }

            let ts = DateParsing.parse(obj["timestamp"])
            if ts < cutoff { continue }

            eventIndex += 1
            let reqId = sessionId.map { "\($0)#\(eventIndex)" }

            // 非缓存输入 = 总输入 - 缓存命中输入；reasoning tokens 归入 output。
            let nonCachedInput = max(0, input - cachedInput)
            let totalOutput = output + reasoning

            records.append(UsageRecord(
                timestamp: ts,
                provider: Provider.openai.rawValue,
                model: normalizeOpenAIModel(currentModel),
                sourceApp: "Codex",
                inputTokens: nonCachedInput,
                outputTokens: totalOutput,
                cacheCreationTokens: 0,
                cacheReadTokens: cachedInput,
                requestId: reqId
            ))
        }
        return records
    }

    private func extractSessionId(from filename: String) -> String? {
        // rollout-2026-06-18T07-00-39-<uuid>.jsonl
        let stem = (filename as NSString).deletingPathExtension
        let parts = stem.split(separator: "-")
        guard parts.count >= 5 else { return nil }
        return parts.suffix(5).joined(separator: "-")
    }

    private func normalizeOpenAIModel(_ raw: String) -> String {
        let lower = raw.lowercased()
        let knownPrefixes = [
            "gpt-5.5-pro", "gpt-5.5",
            "gpt-5.4-nano", "gpt-5.4-mini", "gpt-5.4-pro", "gpt-5.4",
            "gpt-5.3", "gpt-5.2", "gpt-5.1", "gpt-5",
            "gpt-4.1-mini", "gpt-4.1-nano", "gpt-4.1",
            "gpt-4o-mini", "gpt-4o",
            "o4-mini", "o3-mini", "o3", "o1-mini", "o1",
            "codex-mini", "codex"
        ]
        for p in knownPrefixes where lower.contains(p) { return p }
        return raw
    }

    // MARK: - API fallback

    private func fetchFromAPI(key: String, since: Date) async throws -> [UsageRecord] {
        let startTime = Int(since.timeIntervalSince1970)
        let urlStr = "https://api.openai.com/v1/organization/usage/completions?start_time=\(startTime)&bucket_width=1d"
        guard let url = URL(string: urlStr) else { return [] }

        let data = try await APIClient.get(url: url, headers: [
            "Authorization": "Bearer \(key)"
        ])
        return parseAPI(data: data)
    }

    private func parseAPI(data: Data) -> [UsageRecord] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = json["data"] as? [[String: Any]] else { return [] }
        var records: [UsageRecord] = []
        for bucket in buckets {
            let ts = DateParsing.parse(bucket["start_time"])
            guard let results = bucket["results"] as? [[String: Any]] else { continue }
            for r in results {
                let model = (r["model"] as? String) ?? "gpt-4o-mini"
                let input = (r["input_tokens"] as? Int) ?? 0
                let output = (r["output_tokens"] as? Int) ?? 0
                if input == 0 && output == 0 { continue }
                records.append(UsageRecord(
                    timestamp: ts,
                    provider: Provider.openai.rawValue,
                    model: model,
                    sourceApp: "OpenAI API",
                    inputTokens: input,
                    outputTokens: output
                ))
            }
        }
        return records
    }
}
