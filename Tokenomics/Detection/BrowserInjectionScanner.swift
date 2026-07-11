import Foundation

/// P1+P2 扫描器：查找 Claude Desktop 是否在本机浏览器里静默注入了配置产物。
///
/// 检测范围（爆料描述的常见位置）：
///   - `Native Messaging Hosts/*.json`：Chromium 系用来让本地应用与浏览器扩展互通的
///     manifest；如果 Claude Desktop 想让浏览器扩展主动上报数据，会往这里写。
///   - `External Extensions/*.json`：外部程序声明的"随浏览器自动安装的扩展"。
///   - `Extensions/<id>/<version>/manifest.json`：真正落地的扩展 manifest。
///   - `Preferences`（JSON）：用户 profile 级别的全局配置；扫描其中 `extensions.settings`。
///
/// 匹配逻辑：
///   1. 遍历用户已装的 Chromium 系浏览器 profile 目录（Chrome / Edge / Brave / Arc /
///      Vivaldi / Opera / 通用 Chromium）。
///   2. 对每个候选文件，读文本后**大小写不敏感**匹配一组关键字：
///        `anthropic` / `claude` / `com.anthropic` / `api.anthropic.com`。
///   3. 每个命中收集 `BrowserInjectionHit`：包含 profile 路径、文件路径、类型、
///      mtime、命中的关键字集合、以及命中处的 200 字符片段。
///   4. 若 App Sandbox 关闭且系统允许，尝试 `codesign -dv` 读取签名者 Team ID（可选）。
///
/// **只读**：全部 IO 都走 `Data(contentsOf:)`、`FileManager.contentsOfDirectory`；
/// 永远不写、不删。
struct BrowserInjectionScanner {

    /// Chromium 系浏览器：为了不影响现有 [ChromiumCookieReader](file:///.../ChromiumCookieReader.swift)
    /// 的 sessionKey 逻辑（仅 chrome / brave），这里独立定义一个更全的枚举。
    struct BrowserSpec {
        let name: String          // "Chrome" / "Edge" / ...
        let userDataDir: URL
    }

    static func knownBrowsers() -> [BrowserSpec] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            BrowserSpec(name: "Chrome",   userDataDir: home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)),
            BrowserSpec(name: "Edge",     userDataDir: home.appendingPathComponent("Library/Application Support/Microsoft Edge", isDirectory: true)),
            BrowserSpec(name: "Brave",    userDataDir: home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser", isDirectory: true)),
            BrowserSpec(name: "Arc",      userDataDir: home.appendingPathComponent("Library/Application Support/Arc/User Data", isDirectory: true)),
            BrowserSpec(name: "Vivaldi",  userDataDir: home.appendingPathComponent("Library/Application Support/Vivaldi", isDirectory: true)),
            BrowserSpec(name: "Opera",    userDataDir: home.appendingPathComponent("Library/Application Support/com.operasoftware.Opera", isDirectory: true)),
            BrowserSpec(name: "Chromium", userDataDir: home.appendingPathComponent("Library/Application Support/Chromium", isDirectory: true))
        ]
    }

    /// 用于内容匹配的关键字（全部小写；查找时对被查文本做 `lowercased()`）。
    static let contentKeywords: [String] = [
        "anthropic",
        "api.anthropic.com",
        "com.anthropic",
        "claude"
    ]

    /// 已知的"合法"来源：Anthropic 官方 Claude Desktop 通过 MCP / Computer Use 与浏览器
    /// 打通时，可能会写下同样的 native-messaging-host。这里只是提前留 hook，供 UI
    /// 展示时把 severity 从 confirmed 降为 informational（默认为空，全部报告）。
    static let knownLegitimateBundleIDs: Set<String> = []

    /// 主入口：扫描所有已装的 Chromium 系浏览器，返回全部命中。
    static func scanAll() -> [BrowserInjectionHit] {
        var result: [BrowserInjectionHit] = []
        for browser in knownBrowsers() {
            guard FileManager.default.fileExists(atPath: browser.userDataDir.path) else { continue }
            result.append(contentsOf: scan(browser: browser))
        }
        return result
    }

    private static func scan(browser: BrowserSpec) -> [BrowserInjectionHit] {
        var hits: [BrowserInjectionHit] = []
        // 每个 profile 都会有：Extensions/、Preferences。此外，browser 级（不在 profile 里）会有
        // NativeMessagingHosts、External Extensions、External Extensions.json 等。
        // 我们两层都扫。

        // 1. 浏览器根级
        for sub in ["NativeMessagingHosts", "External Extensions"] {
            let dir = browser.userDataDir.appendingPathComponent(sub, isDirectory: true)
            hits.append(contentsOf: scanDir(dir, browser: browser, artifactType: sub))
        }

        // 2. 每个 profile
        for profile in enumerateProfiles(under: browser.userDataDir) {
            // 2a. NativeMessagingHosts（profile 级也可能有）
            for sub in ["NativeMessagingHosts", "External Extensions"] {
                let dir = profile.appendingPathComponent(sub, isDirectory: true)
                hits.append(contentsOf: scanDir(dir, browser: browser, artifactType: sub, profile: profile))
            }
            // 2b. Extensions/<id>/<version>/manifest.json
            let extRoot = profile.appendingPathComponent("Extensions", isDirectory: true)
            hits.append(contentsOf: scanExtensionsRoot(extRoot, browser: browser, profile: profile))
            // 2c. Preferences（JSON）
            let prefFile = profile.appendingPathComponent("Preferences")
            if let hit = scanFile(prefFile, browser: browser, artifactType: "Preferences", profile: profile) {
                hits.append(hit)
            }
        }
        return hits
    }

    /// 枚举 `Default` / `Profile 1` / `Profile 2` ...
    private static func enumerateProfiles(under userDataDir: URL) -> [URL] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: userDataDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.filter { url in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
            let name = url.lastPathComponent
            return name == "Default" || name.hasPrefix("Profile ")
        }
    }

    /// 遍历目录下所有 `.json` 文件，逐一做关键字匹配。
    private static func scanDir(_ dir: URL,
                                browser: BrowserSpec,
                                artifactType: String,
                                profile: URL? = nil) -> [BrowserInjectionHit] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        guard let items = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var hits: [BrowserInjectionHit] = []
        for f in items {
            if let hit = scanFile(f, browser: browser, artifactType: artifactType, profile: profile) {
                hits.append(hit)
            }
        }
        return hits
    }

    /// 遍历 Extensions 根下的每个扩展 manifest。
    private static func scanExtensionsRoot(_ root: URL,
                                           browser: BrowserSpec,
                                           profile: URL) -> [BrowserInjectionHit] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        guard let extIDs = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var hits: [BrowserInjectionHit] = []
        for idDir in extIDs {
            guard fm.fileExists(atPath: idDir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let versionDirs = try? fm.contentsOfDirectory(
                at: idDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for vDir in versionDirs {
                let manifest = vDir.appendingPathComponent("manifest.json")
                if let hit = scanFile(manifest, browser: browser, artifactType: "Extension", profile: profile) {
                    hits.append(hit)
                }
            }
        }
        return hits
    }

    /// 对单个文件做关键字匹配。命中返回 `BrowserInjectionHit`，未命中返回 nil。
    private static func scanFile(_ file: URL,
                                 browser: BrowserSpec,
                                 artifactType: String,
                                 profile: URL? = nil) -> BrowserInjectionHit? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return nil }
        guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else { return nil }
        // 文件通常是小 JSON；Preferences 可能几十 KB。都直接转 UTF-8 尝试。
        let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let lower = raw.lowercased()
        var matched: [String] = []
        for kw in contentKeywords where lower.contains(kw) {
            matched.append(kw)
        }
        guard !matched.isEmpty else { return nil }

        // 取命中处的片段：以第一个关键字为中心，前后各 100 字符。
        var excerptStr: String? = nil
        if let firstKw = matched.first, let r = lower.range(of: firstKw) {
            let center = raw.distance(from: raw.startIndex, to: r.lowerBound)
            let start = max(0, center - 100)
            let end = min(raw.count, center + firstKw.count + 100)
            let s = raw.index(raw.startIndex, offsetBy: start)
            let e = raw.index(raw.startIndex, offsetBy: end)
            excerptStr = String(raw[s..<e])
        }

        var mtime: Date? = nil
        if let attrs = try? fm.attributesOfItem(atPath: file.path) {
            mtime = attrs[.modificationDate] as? Date
        }

        return BrowserInjectionHit(
            browser: browser.name,
            profilePath: profile ?? browser.userDataDir,
            artifactPath: file,
            artifactType: artifactType,
            mtime: mtime,
            signerTeamID: nil,  // 保留字段；后续可通过 Process + codesign 增强
            matchedKeywords: matched,
            excerpt: excerptStr
        )
    }
}
