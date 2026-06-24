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
    /// path -> 上次解析 cursor。由 Scheduler 通过 cursorPayload 注入并持久化。
    private var cursor: [String: FileCursor] = [:]

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

    var cursorPayload: String? {
        get { FileCursor.encode(cursor) }
        set { cursor = FileCursor.decode(newValue) }
    }

    func collect(since: Date?) async throws -> [UsageRecord] {
        let cutoff = since ?? defaultSince
        var results: [UsageRecord] = []

        if FileManager.default.fileExists(atPath: codexDir.path) {
            let candidates = enumerateJSONL(in: codexDir, cutoff: cutoff)
            var nextCursor: [String: FileCursor] = [:]
            for entry in candidates {
                let key = entry.url.path
                let prev = cursor[key]
                // mtime + size 完全不变 → 跳过 IO，沿用旧 cursor。
                if let prev, prev.mtime == entry.mtime, prev.size == entry.size {
                    nextCursor[key] = prev
                    continue
                }
                let startOffset: Int64 = (prev.map { Int64($0.size) }).flatMap { $0 <= entry.size ? $0 : nil } ?? 0
                results.append(contentsOf: parseFile(url: entry.url, cutoff: cutoff, startOffset: startOffset))
                nextCursor[key] = FileCursor(mtime: entry.mtime, size: entry.size)
            }
            cursor = nextCursor
        }

        if let key = keychain.get(KeychainKey.openai), !key.isEmpty {
            if let apiRecords = try? await fetchFromAPI(key: key, since: cutoff) {
                results.append(contentsOf: apiRecords)
            }
        }

        return results
    }

    // MARK: - Local Codex parsing

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
            if let mtime = values?.contentModificationDate, mtime < cutoff { continue }
            let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = Int64(values?.fileSize ?? 0)
            files.append(FileEntry(url: url, mtime: mtime, size: size))
        }
        return files
    }

    private func parseFile(url: URL, cutoff: Date, startOffset: Int64) -> [UsageRecord] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        if startOffset > 0 {
            do { try handle.seek(toOffset: UInt64(startOffset)) } catch { return [] }
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }

        // 注：Codex 解析依赖 `turn_context` / `session_meta` 这类"状态"事件来确定 currentModel，
        // 如果我们从文件中段开始读，这些状态事件就丢了。为安全起见，
        // 只有"文件从未被解析过"（startOffset == 0）才允许 fromIndex 计算 sessionId；
        // 增量场景下 sessionId / model 仍按本片段的事件流推演，不影响 token_count 正确性
        // —— 大部分 jsonl 在 token_count 同行也会带 cwd / model 提示，缺失时降级为 "gpt-5.5"。
        let sessionId = startOffset == 0 ? extractSessionId(from: url.lastPathComponent) : nil
        var currentModel: String = "gpt-5.5"
        var records: [UsageRecord] = []
        var eventIndex = 0

        let skipFirstFragment = startOffset > 0
        let bytes = [UInt8](data)
        let newline: UInt8 = 0x0A
        var index = 0
        var lineStart = 0

        func consume(_ start: Int, _ end: Int) {
            guard end > start else { return }
            let slice = Data(bytes[start..<end])
            guard let obj = try? JSONSerialization.jsonObject(with: slice) as? [String: Any] else { return }
            let type = obj["type"] as? String
            let payload = obj["payload"] as? [String: Any]

            if type == "turn_context", let model = payload?["model"] as? String, !model.isEmpty {
                currentModel = model
                return
            }
            if type == "session_meta", let model = (payload?["payload"] as? [String: Any])?["model"] as? String, !model.isEmpty {
                currentModel = model
                return
            }

            guard type == "event_msg",
                  let payload = payload,
                  (payload["type"] as? String) == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any] else { return }

            let input = (last["input_tokens"] as? Int) ?? 0
            let output = (last["output_tokens"] as? Int) ?? 0
            let cachedInput = (last["cached_input_tokens"] as? Int) ?? 0
            let reasoning = (last["reasoning_output_tokens"] as? Int) ?? 0
            if input == 0 && output == 0 && cachedInput == 0 { return }

            let ts = DateParsing.parse(obj["timestamp"])
            if ts < cutoff { return }

            eventIndex += 1
            let reqId = sessionId.map { "\($0)#\(eventIndex)" }
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

        while index < bytes.count {
            if bytes[index] == newline {
                if !(skipFirstFragment && lineStart == 0) {
                    consume(lineStart, index)
                }
                lineStart = index + 1
            }
            index += 1
        }
        if lineStart < bytes.count {
            let isCompleteLine = !(skipFirstFragment && lineStart == 0)
            if isCompleteLine { consume(lineStart, bytes.count) }
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
