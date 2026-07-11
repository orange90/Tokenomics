import Foundation
import Combine

/// Claude Desktop 隐写术 & 浏览器注入检测的顶层协调器。
///
/// 职责：
///   - 编排 `BrowserInjectionScanner` (P1+P2) 与 `ClaudeLocalPromptScanner` (P3)。
///   - 承接 UI 侧发起的**手动导入 mitmproxy 日志**（P4），把命中并入当前报告。
///   - 汇总为一个 `StegoReport`，写入 `@Published var latestReport`。
///   - 提供**按需触发**的 `runFullScan()` 与 **导出报告**方法。
///
/// 默认**不常驻**：不做文件监听。用户可在 Settings 里勾选"每 24h 自动扫描一次"，
/// 由 `AppState` 在 refresh cycle 里 tick。
@MainActor
final class ClaudeStegoProbe: ObservableObject {

    @Published private(set) var latestReport: StegoReport?
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var progress: Double = 0

    /// 上次扫描时间；用于"每 24h 自动"限流。
    @Published private(set) var lastScanAt: Date?

    /// 日志钩子（复用 AppState.appendStatus 的模式）。init 时可选传入；亦可在 bootstrap
    /// 之后通过 `setLogger(_:)` 注入。
    private var onLog: ((String) -> Void)?

    init(onLog: ((String) -> Void)? = nil) {
        self.onLog = onLog
    }

    /// 允许 AppState 在 bootstrap 后再把日志通道接进来。
    func setLogger(_ onLog: @escaping (String) -> Void) {
        self.onLog = onLog
    }

    // MARK: - 主入口：全量扫描

    /// 执行一次全量扫描（P1+P2+P3），可选合并之前从 mitm 日志导入的命中。
    /// - Parameter preserveImportedHits: 上一次 `importMitmLog` 得到的 hits 是否要继续合并进来。
    ///                                   默认 true，避免用户"重新扫描"时把外部证据清掉。
    func runFullScan(preserveImportedHits: Bool = true) async {
        if isScanning { return }
        isScanning = true
        progress = 0
        defer {
            isScanning = false
            progress = 1.0
        }
        onLog?("开始 Claude Desktop 隐写术 / 浏览器注入扫描")

        // 允许并行执行浏览器扫描（重 IO）与本地缓存扫描（重 IO）。
        async let browserHits = Task.detached(priority: .utility) {
            BrowserInjectionScanner.scanAll()
        }.value
        async let promptHits = Task.detached(priority: .utility) { [weak self] in
            ClaudeLocalPromptScanner.scanClaudeDesktopCaches(progress: { p in
                Task { @MainActor in self?.progress = p * 0.9 }
            })
        }.value

        let bHits = await browserHits
        var pHits = await promptHits

        // 保留之前导入的 mitm 命中（如果有）
        if preserveImportedHits, let existing = latestReport?.promptHits {
            pHits.append(contentsOf: existing.filter { $0.source == .mitmLog })
        }

        let severity = deriveSeverity(browserHits: bHits, promptHits: pHits)
        let summary = summarize(browserHits: bHits, promptHits: pHits, severity: severity)

        let report = StegoReport(
            generatedAt: Date(),
            signaturesVersion: StegoSignatures.signaturesVersion,
            browserHits: bHits,
            promptHits: pHits,
            severity: severity,
            summary: summary
        )
        self.latestReport = report
        self.lastScanAt = Date()
        onLog?("扫描完成：浏览器命中 \(bHits.count) 处，隐写命中 \(pHits.count) 处，等级 \(severity.rawValue)")
    }

    // MARK: - mitmproxy 日志导入

    /// 导入用户手动抓的 mitmproxy JSON / HAR，把命中合并进当前报告。
    /// 若当前 `latestReport` 为空，会自动触发一次全量扫描后再合并。
    /// - Returns: 本次导入新增的 hit 数量。
    @discardableResult
    func importMitmLog(fileURL: URL) async throws -> Int {
        let hits: [PromptStegoHit]
        do {
            hits = try MitmLogImporter.importAndScan(fileURL: fileURL)
        } catch {
            onLog?("导入 mitm 日志失败：\(error.localizedDescription)")
            throw error
        }
        onLog?("导入 mitm 日志：\(fileURL.lastPathComponent) → 命中 \(hits.count) 处")

        let base = latestReport ?? StegoReport(
            generatedAt: Date(),
            signaturesVersion: StegoSignatures.signaturesVersion,
            browserHits: [],
            promptHits: [],
            severity: .clean,
            summary: ""
        )
        var merged = base.promptHits
        merged.append(contentsOf: hits)
        let severity = deriveSeverity(browserHits: base.browserHits, promptHits: merged)
        let summary = summarize(browserHits: base.browserHits, promptHits: merged, severity: severity)
        self.latestReport = StegoReport(
            generatedAt: Date(),
            signaturesVersion: StegoSignatures.signaturesVersion,
            browserHits: base.browserHits,
            promptHits: merged,
            severity: severity,
            summary: summary
        )
        return hits.count
    }

    // MARK: - 导出

    /// 把当前报告写到用户选择的目标 URL。UI 层负责用 NSSavePanel 拿路径。
    /// - Returns: 写入的字节数；nil 表示没有可导出的报告或写入失败。
    @discardableResult
    func exportReport(to url: URL) -> Int? {
        guard let report = latestReport, let data = report.exportJSON() else { return nil }
        do {
            try data.write(to: url, options: [.atomic])
            onLog?("已导出隐写检测报告：\(url.path)")
            return data.count
        } catch {
            onLog?("导出报告失败：\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - severity 与摘要

    private func deriveSeverity(
        browserHits: [BrowserInjectionHit],
        promptHits: [PromptStegoHit]
    ) -> StegoSeverity {
        let hasConfirmedStego = promptHits.contains { hit in
            hit.channel != .unknownNonAscii
        }
        if hasConfirmedStego { return .confirmed }
        if !browserHits.isEmpty || promptHits.contains(where: { $0.channel == .unknownNonAscii }) {
            return .suspicious
        }
        return .clean
    }

    private func summarize(
        browserHits: [BrowserInjectionHit],
        promptHits: [PromptStegoHit],
        severity: StegoSeverity
    ) -> String {
        switch severity {
        case .clean:
            return "未发现任何可疑证据：既没有在浏览器 profile 中读到 Anthropic 相关注入产物，本地 Claude Desktop 缓存里也没有出现爆料中列出的 Unicode 隐写字符。"
        case .suspicious:
            var parts: [String] = []
            if !browserHits.isEmpty {
                parts.append("在 \(Set(browserHits.map { $0.browser }).count) 个浏览器的 profile 中发现 \(browserHits.count) 处含 Anthropic 关键字的配置产物")
            }
            if promptHits.contains(where: { $0.channel == .unknownNonAscii }) {
                parts.append("在 Today's date 附近发现未知非 ASCII 字符（可能是新的隐写通道）")
            }
            return parts.joined(separator: "；") + "。尚未捕获到爆料中明确列出的 Unicode 码位，建议继续用 mitmproxy 抓一次请求做交叉验证。"
        case .confirmed:
            let byChannel = Dictionary(grouping: promptHits, by: { $0.channel })
                .map { "\($0.value.count)× \($0.key.rawValue)" }
                .joined(separator: "、")
            return "命中爆料 Unicode 码位：\(byChannel)。浏览器注入产物 \(browserHits.count) 处。"
        }
    }
}
