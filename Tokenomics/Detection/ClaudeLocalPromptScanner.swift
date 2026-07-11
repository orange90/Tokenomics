import Foundation

/// P3 本地 Prompt 扫描器。
///
/// 职责：
///   1. `scan(text:source:filePath:timestamp:)`：**纯函数**。给一段任意文本，找出爆料
///      中列出的四种隐写通道命中，返回 `[PromptStegoHit]`。这个函数没有任何 IO，
///      能被单元测试直接调用（详见 Step 10 的手工验证 case）。
///   2. `scanClaudeDesktopCaches()`：遍历用户 `~/Library` 下 Claude Desktop 可能落盘
///      系统提示词的目录，把每个可读文本文件喂给 `scan(text:)`。因为 project.yml 已经
///      把 App Sandbox 关掉（`com.apple.security.app-sandbox: false`），我们可以直接
///      读；如果未来改为沙盒签名版本，会通过 `NSOpenPanel` 让用户显式授予书签授权
///      （见 `SandboxAccess` helper 里描述的运行时探测策略）。
///
/// 检测规则（对齐 [StegoSignatures](file:///.../StegoSignatures.swift)）：
///   - 步骤 A：在文本里搜索 `today[' ’ ʼ ʹ]s\s+date` 的锚点（不区分大小写）。
///     如果通篇没有该锚点，就当作**普通文本**，不做隐写分析，直接跳过。
///     —— 这一步避免把用户日常英文里的 U+2019 单引号误判成隐写。
///   - 步骤 B：对每个锚点匹配，取匹配中间的那个"单引号位"字符：
///        · 如果是 U+0027 → 认为该处**未被篡改**，不打分。
///        · 如果是 U+2019 / U+02BC / U+02B9 → 命中对应 `StegoChannel`。
///        · 如果是其他非 ASCII 字符 → 命中 `.unknownNonAscii`（兜底通道，未来扩展）。
///   - 步骤 C：在锚点匹配位置**后方 30 字符**内继续搜 `YYYY[-/]MM[-/]DD` 格式的
///     日期；若中间分隔符是 `/` 则命中 `.dateSeparatorSlash`；`-` 则视为正常，不打分。
///
/// **注意**：本扫描器**不**试图"猜"哪个文件是系统提示词——只要有 `Today's date`
/// 锚点，就当作值得检测。这一决定让实现保持极简且不会假阴性。
struct ClaudeLocalPromptScanner {

    // MARK: - Public: 纯函数扫描接口

    /// 扫描一段任意文本，返回全部命中。
    /// - Parameters:
    ///   - text: 要扫描的原文，须保留原始 Unicode 编码（不要预先做 NFC/NFKC 归一化）。
    ///   - source: 命中来源；本地缓存传 `.localCache`，mitmproxy 导入器传 `.mitmLog`。
    ///   - filePath: 命中所在的文件；纯字符串输入可传 nil。
    ///   - timestamp: 抓包/事件时间；本地文件通常传 mtime。
    static func scan(
        text: String,
        source: PromptStegoHit.Source,
        filePath: URL? = nil,
        timestamp: Date? = nil
    ) -> [PromptStegoHit] {
        // 步骤 A：找锚点。不区分大小写，允许四种撇号形态。
        guard let regex = try? NSRegularExpression(
            pattern: StegoSignatures.todaysDateAnchorPattern,
            options: [.caseInsensitive]
        ) else { return [] }

        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return [] }

        var hits: [PromptStegoHit] = []
        // 分隔符探测的正则；一次编译，多次复用。
        let sepRegex = try? NSRegularExpression(
            pattern: StegoSignatures.dateSeparatorProbePattern,
            options: []
        )

        for m in matches {
            let matchedText = ns.substring(with: m.range)

            // 步骤 B：定位撇号字符。锚点形如 "today's date"，找到 't' 后紧跟的字符。
            if let apostropheIdx = matchedText.unicodeScalars.firstIndex(where: { s in
                s == Unicode.Scalar(0x0027)!
                    || StegoSignatures.channel(for: s) != nil
                    || (!s.isASCII && s != Unicode.Scalar("\n"))
            }) {
                let scalar = matchedText.unicodeScalars[apostropheIdx]
                if scalar != Unicode.Scalar(0x0027)! {
                    // 命中一条撇号通道
                    let channel: StegoChannel
                    let codepoint: String
                    let tag: String
                    if let ch = StegoSignatures.channel(for: scalar) {
                        codepoint = ch.codepoint
                        tag = ch.inferredTag
                        switch ch.codepoint {
                        case "U+2019": channel = .apostropheU2019
                        case "U+02BC": channel = .apostropheU02BC
                        case "U+02B9": channel = .apostropheU02B9
                        default:       channel = .unknownNonAscii
                        }
                    } else {
                        channel = .unknownNonAscii
                        codepoint = String(format: "U+%04X", scalar.value)
                        tag = "Unknown non-ASCII near date anchor"
                    }
                    hits.append(PromptStegoHit(
                        source: source,
                        filePath: filePath,
                        excerpt: excerpt(from: ns, around: m.range, radius: 40),
                        hitOffset: m.range.location,
                        channel: channel,
                        codepoint: codepoint,
                        inferredTag: tag,
                        timestamp: timestamp
                    ))
                }
            }

            // 步骤 C：锚点后方 30 字符内找日期分隔符。
            let tailStart = m.range.location + m.range.length
            let tailLen = min(ns.length - tailStart, 30)
            if tailLen > 0, let sepRe = sepRegex {
                let tailRange = NSRange(location: tailStart, length: tailLen)
                if let sepMatch = sepRe.firstMatch(in: text, options: [], range: tailRange),
                   sepMatch.numberOfRanges >= 3 {
                    let sep = ns.substring(with: sepMatch.range(at: 2))
                    if sep == "/" {
                        hits.append(PromptStegoHit(
                            source: source,
                            filePath: filePath,
                            excerpt: excerpt(from: ns, around: sepMatch.range, radius: 40),
                            hitOffset: sepMatch.range.location,
                            channel: .dateSeparatorSlash,
                            codepoint: "U+002F",
                            inferredTag: "Date separator '/' — inferred CN timezone",
                            timestamp: timestamp
                        ))
                    }
                }
            }
        }
        return hits
    }

    /// 从 NSString 里取一段前后 `radius` 字符的上下文（用于 UI 展示证据）。
    /// 保留原始 Unicode，绝不做归一化。
    private static func excerpt(from ns: NSString, around r: NSRange, radius: Int) -> String {
        let start = max(0, r.location - radius)
        let end = min(ns.length, r.location + r.length + radius)
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    // MARK: - Public: 本地缓存目录扫描

    /// Claude Desktop 与相关应用可能把系统提示词或最近会话落盘的目录。
    /// 只列**只读**扫描目标；本代码永远不会写。
    static let defaultCacheRoots: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/com.anthropic.claudefordesktop", isDirectory: true),
            home.appendingPathComponent("Library/Logs/Claude", isDirectory: true),
            home.appendingPathComponent("Library/Caches/Claude", isDirectory: true),
            home.appendingPathComponent("Library/Caches/com.anthropic.claudefordesktop", isDirectory: true),
            home.appendingPathComponent("Library/Preferences", isDirectory: true) // 单独遍历时按 bundle id 过滤
        ]
    }()

    /// 全量扫描本地缓存。返回所有命中的隐写事件。
    /// - Parameter maxFileBytes: 单文件读取上限，避免读到超大 LevelDB（默认 32 MiB）。
    /// - Parameter progress: 每处理完一个文件回调一次进度（0...1），可传 nil。
    static func scanClaudeDesktopCaches(
        maxFileBytes: Int = 32 * 1024 * 1024,
        progress: ((Double) -> Void)? = nil
    ) -> [PromptStegoHit] {
        var results: [PromptStegoHit] = []
        let candidateFiles = enumerateCandidateFiles(roots: defaultCacheRoots)
        let total = max(candidateFiles.count, 1)
        for (idx, url) in candidateFiles.enumerated() {
            if let text = readPrintableText(url: url, maxBytes: maxFileBytes) {
                var mtime: Date? = nil
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                    mtime = attrs[.modificationDate] as? Date
                }
                let hits = scan(text: text, source: .localCache, filePath: url, timestamp: mtime)
                results.append(contentsOf: hits)
            }
            progress?(Double(idx + 1) / Double(total))
        }
        return results
    }

    /// 枚举给定根目录下所有**可能是文本**的文件。对 `Library/Preferences` 只挑
    /// `com.anthropic.*` 的 plist，避免读到别的应用配置。
    private static func enumerateCandidateFiles(roots: [URL]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for root in roots {
            guard fm.fileExists(atPath: root.path) else { continue }
            // Preferences 目录做特殊过滤
            if root.lastPathComponent == "Preferences" {
                if let items = try? fm.contentsOfDirectory(at: root,
                                                          includingPropertiesForKeys: [.isRegularFileKey],
                                                          options: [.skipsHiddenFiles]) {
                    for u in items where u.lastPathComponent.lowercased().contains("anthropic")
                                     || u.lastPathComponent.lowercased().contains("claude") {
                        result.append(u)
                    }
                }
                continue
            }
            let en = fm.enumerator(at: root,
                                   includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                   options: [.skipsHiddenFiles])
            while let obj = en?.nextObject() as? URL {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: obj.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                result.append(obj)
            }
        }
        return result
    }

    /// 尝试把文件当文本读取。对 LevelDB / SQLite 这类二进制文件，会**回退到字节流**，
    /// 只保留可打印 ASCII / UTF-8 段落。这样即使 IndexedDB 里内嵌了系统提示词，
    /// 也能被扫到（不需要真的解析 LevelDB 结构）。
    private static func readPrintableText(url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data: Data
        do {
            data = try handle.read(upToCount: maxBytes) ?? Data()
        } catch {
            return nil
        }
        if data.isEmpty { return nil }
        // 快速判定：UTF-8 直接解出来就用；否则退化成"可打印字节"过滤。
        if let s = String(data: data, encoding: .utf8) {
            return s
        }
        // Fallback：把非可打印字节替换成 \n，仍然保留原始 Unicode 码位。
        var out = String()
        out.reserveCapacity(data.count)
        var idx = data.startIndex
        while idx < data.endIndex {
            // 尝试一次多字节 UTF-8 解码；失败则跳过 1 字节。
            for len in [4, 3, 2, 1] {
                let end = data.index(idx, offsetBy: len, limitedBy: data.endIndex) ?? data.endIndex
                let slice = data[idx..<end]
                if let s = String(data: slice, encoding: .utf8), !s.isEmpty {
                    out += s
                    idx = end
                    break
                }
                if len == 1 {
                    out.append("\n")
                    idx = data.index(after: idx)
                }
            }
        }
        return out.isEmpty ? nil : out
    }
}
