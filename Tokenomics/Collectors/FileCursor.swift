import Foundation

/// Collector 增量解析使用的"每文件水位"。
/// 由 ClaudeCodeCollector / OpenAIAPICollector 共用：
///   - mtime：文件最近修改时间（秒），用于"完全未变更则跳过 IO"短路；
///   - size：上一轮已解析到的字节数，用于 seek 到该处只读取增量。
/// 任意值不匹配（mtime 改变或 size 缩小）就 fallback 到全文件重读。
struct FileCursor: Codable {
    var mtime: TimeInterval
    var size: Int64

    static func encode(_ map: [String: FileCursor]) -> String? {
        guard !map.isEmpty,
              let data = try? JSONEncoder().encode(map),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    static func decode(_ raw: String?) -> [String: FileCursor] {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: FileCursor].self, from: data) else { return [:] }
        return map
    }
}
