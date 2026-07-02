import Foundation
import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// 报表导出 / 月度对账工具。
///
/// 提供四种导出格式：
/// - CSV：行级原始数据，方便 Numbers / Excel 进一步分析
/// - JSON：行级原始数据 + 当月聚合，方便二次开发或归档
/// - Markdown：当月汇总（按 provider × model 折叠），适合粘贴到团队群
/// - PDF：月度账单，适合报销 / 跟老板对账
///
/// 所有方法都是同步的，文本生成开销可忽略；PDF 走 PDFKit 直接画文本，无需 WebView。
enum ReportExporter {

    // MARK: - 当月聚合数据结构

    /// 按 (provider, model) 汇总的一行
    struct MonthlyLineItem {
        let providerKey: String
        let providerDisplay: String
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int
        let costUSD: Double
        let count: Int

        var totalTokens: Int {
            inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
        }
    }

    /// 按 provider 汇总的一行（用于报销 PDF 的「按供应商分组」小节）
    struct ProviderSubtotal {
        let providerKey: String
        let providerDisplay: String
        let costUSD: Double
        let tokens: Int
        let count: Int
    }

    /// 月度汇总结果。`month` 表示该月起始零点（自然月，本地时区）。
    struct MonthlyReport {
        let month: Date
        let monthLabel: String  // "2026-06"
        let lineItems: [MonthlyLineItem]
        let subtotalByProvider: [ProviderSubtotal]
        let totalCostUSD: Double
        let totalTokens: Int
        let totalRecords: Int
    }

    // MARK: - 聚合

    /// 把 records 中落在指定自然月（本地时区）的部分聚合为 MonthlyReport。
    /// - Parameters:
    ///   - records: 全量 UsageRecord
    ///   - month: 该月任意时刻（内部会归一化到月起点）
    ///   - providerDisplay: providerKey -> 显示名（内置 Provider + 自定义 CustomProvider）
    static func buildMonthlyReport(
        records: [UsageRecord],
        month: Date,
        providerDisplay: (String) -> String
    ) -> MonthlyReport {
        let cal = Calendar.current
        let interval = cal.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 0)
        let start = interval.start
        let end = interval.end

        // (providerKey, model) -> 聚合
        var bucket: [String: MonthlyLineItem] = [:]
        var providerBucket: [String: ProviderSubtotal] = [:]
        var totalCost: Double = 0
        var totalTokens: Int = 0
        var totalCount: Int = 0

        for r in records {
            guard r.timestamp >= start && r.timestamp < end else { continue }
            let key = "\(r.provider)|\(r.model)"
            if var item = bucket[key] {
                item = MonthlyLineItem(
                    providerKey: item.providerKey,
                    providerDisplay: item.providerDisplay,
                    model: item.model,
                    inputTokens: item.inputTokens + r.inputTokens,
                    outputTokens: item.outputTokens + r.outputTokens,
                    cacheCreationTokens: item.cacheCreationTokens + r.cacheCreationTokens,
                    cacheReadTokens: item.cacheReadTokens + r.cacheReadTokens,
                    costUSD: item.costUSD + r.costUSD,
                    count: item.count + 1
                )
                bucket[key] = item
            } else {
                bucket[key] = MonthlyLineItem(
                    providerKey: r.provider,
                    providerDisplay: providerDisplay(r.provider),
                    model: r.model,
                    inputTokens: r.inputTokens,
                    outputTokens: r.outputTokens,
                    cacheCreationTokens: r.cacheCreationTokens,
                    cacheReadTokens: r.cacheReadTokens,
                    costUSD: r.costUSD,
                    count: 1
                )
            }

            if var p = providerBucket[r.provider] {
                p = ProviderSubtotal(
                    providerKey: p.providerKey,
                    providerDisplay: p.providerDisplay,
                    costUSD: p.costUSD + r.costUSD,
                    tokens: p.tokens + r.totalTokens,
                    count: p.count + 1
                )
                providerBucket[r.provider] = p
            } else {
                providerBucket[r.provider] = ProviderSubtotal(
                    providerKey: r.provider,
                    providerDisplay: providerDisplay(r.provider),
                    costUSD: r.costUSD,
                    tokens: r.totalTokens,
                    count: 1
                )
            }

            totalCost += r.costUSD
            totalTokens += r.totalTokens
            totalCount += 1
        }

        let items = bucket.values.sorted { $0.costUSD > $1.costUSD }
        let providers = providerBucket.values.sorted { $0.costUSD > $1.costUSD }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        let label = fmt.string(from: start)

        return MonthlyReport(
            month: start,
            monthLabel: label,
            lineItems: items,
            subtotalByProvider: providers,
            totalCostUSD: totalCost,
            totalTokens: totalTokens,
            totalRecords: totalCount
        )
    }

    // MARK: - CSV

    /// 行级 CSV（与原 DataSettings.exportCSV 行为一致，作为可复用 API 暴露出来）。
    static func makeCSV(records: [UsageRecord]) -> String {
        var csv = "timestamp,provider,model,source,inputTokens,outputTokens,cacheCreation,cacheRead,costUSD\n"
        let iso = ISO8601DateFormatter()
        for r in records {
            csv += "\(iso.string(from: r.timestamp)),\(escapeCSV(r.provider)),\(escapeCSV(r.model)),\(escapeCSV(r.sourceApp)),\(r.inputTokens),\(r.outputTokens),\(r.cacheCreationTokens),\(r.cacheReadTokens),\(r.costUSD)\n"
        }
        return csv
    }

    /// 月度 CSV（聚合行）：方便 Excel 透视。
    static func makeMonthlyCSV(report: MonthlyReport, rate: Double) -> String {
        var csv = "provider,model,records,inputTokens,outputTokens,cacheCreation,cacheRead,totalTokens,costUSD,costCNY\n"
        for it in report.lineItems {
            csv += "\(escapeCSV(it.providerDisplay)),\(escapeCSV(it.model)),\(it.count),\(it.inputTokens),\(it.outputTokens),\(it.cacheCreationTokens),\(it.cacheReadTokens),\(it.totalTokens),\(String(format: "%.6f", it.costUSD)),\(String(format: "%.2f", it.costUSD * rate))\n"
        }
        return csv
    }

    private static func escapeCSV(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return s
    }

    // MARK: - JSON

    /// 全量 JSON：行级数据 + 月度聚合（如果传入 monthlyReport）。
    static func makeJSON(records: [UsageRecord], monthlyReport: MonthlyReport?, rate: Double) -> Data {
        let iso = ISO8601DateFormatter()
        var rows: [[String: Any]] = []
        rows.reserveCapacity(records.count)
        for r in records {
            rows.append([
                "timestamp": iso.string(from: r.timestamp),
                "provider": r.provider,
                "model": r.model,
                "source": r.sourceApp,
                "inputTokens": r.inputTokens,
                "outputTokens": r.outputTokens,
                "cacheCreationTokens": r.cacheCreationTokens,
                "cacheReadTokens": r.cacheReadTokens,
                "costUSD": r.costUSD,
                "requestId": r.requestId ?? ""
            ])
        }
        var root: [String: Any] = [
            "exportedAt": iso.string(from: Date()),
            "usdCnyRate": rate,
            "records": rows
        ]
        if let m = monthlyReport {
            root["monthlySummary"] = [
                "month": m.monthLabel,
                "totalRecords": m.totalRecords,
                "totalTokens": m.totalTokens,
                "totalCostUSD": m.totalCostUSD,
                "totalCostCNY": m.totalCostUSD * rate,
                "byProviderModel": m.lineItems.map { it -> [String: Any] in
                    [
                        "provider": it.providerDisplay,
                        "providerKey": it.providerKey,
                        "model": it.model,
                        "records": it.count,
                        "inputTokens": it.inputTokens,
                        "outputTokens": it.outputTokens,
                        "cacheCreationTokens": it.cacheCreationTokens,
                        "cacheReadTokens": it.cacheReadTokens,
                        "totalTokens": it.totalTokens,
                        "costUSD": it.costUSD,
                        "costCNY": it.costUSD * rate
                    ]
                },
                "byProvider": m.subtotalByProvider.map { p -> [String: Any] in
                    [
                        "provider": p.providerDisplay,
                        "providerKey": p.providerKey,
                        "records": p.count,
                        "tokens": p.tokens,
                        "costUSD": p.costUSD,
                        "costCNY": p.costUSD * rate
                    ]
                }
            ]
        }
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    // MARK: - Markdown

    /// 当月汇总 Markdown。设计目标：粘贴到飞书 / 钉钉 / Slack 后排版可读。
    static func makeMonthlyMarkdown(
        report: MonthlyReport,
        currency: Currency,
        rate: Double
    ) -> String {
        var out = ""
        out += "## 📊 Tokenomics · \(report.monthLabel) 月度汇总\n\n"

        let totalLine = CurrencyFormatting.format(usd: report.totalCostUSD, currency: currency, usdCnyRate: rate)
        out += "- **总花费**：\(totalLine)\n"
        out += "- **总 Token**：\(formatInt(report.totalTokens))\n"
        out += "- **记录条数**：\(report.totalRecords)\n\n"

        if !report.subtotalByProvider.isEmpty {
            out += "### 按供应商\n\n"
            out += "| 供应商 | 花费 | Token | 调用数 |\n"
            out += "| --- | ---: | ---: | ---: |\n"
            for p in report.subtotalByProvider {
                let cost = CurrencyFormatting.format(usd: p.costUSD, currency: currency, usdCnyRate: rate)
                out += "| \(p.providerDisplay) | \(cost) | \(formatInt(p.tokens)) | \(p.count) |\n"
            }
            out += "\n"
        }

        if !report.lineItems.isEmpty {
            out += "### 按模型\n\n"
            out += "| 供应商 | 模型 | 调用数 | 输入 | 输出 | 缓存读/写 | 花费 |\n"
            out += "| --- | --- | ---: | ---: | ---: | ---: | ---: |\n"
            for it in report.lineItems {
                let cost = CurrencyFormatting.format(usd: it.costUSD, currency: currency, usdCnyRate: rate)
                let cache = "\(formatInt(it.cacheReadTokens))/\(formatInt(it.cacheCreationTokens))"
                out += "| \(it.providerDisplay) | \(it.model) | \(it.count) | \(formatInt(it.inputTokens)) | \(formatInt(it.outputTokens)) | \(cache) | \(cost) |\n"
            }
            out += "\n"
        }

        let stampFmt = DateFormatter()
        stampFmt.dateFormat = "yyyy-MM-dd HH:mm"
        out += "_由 Tokenomics 生成 · \(stampFmt.string(from: Date()))_\n"
        return out
    }

    // MARK: - PDF（月度账单 / 报销）

    /// 生成 A4 PDF 月度账单。
    /// 使用 PDFKit 而非 WebView，避免引入异步渲染、字体加载抖动。
    /// 字体走系统字体（NSFont），中文也能正常渲染。
    static func makeMonthlyPDF(
        report: MonthlyReport,
        currency: Currency,
        rate: Double,
        accountName: String?
    ) -> Data {
        // A4 @ 72 dpi  595 x 842 pt
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 40
        let contentWidth = pageRect.width - margin * 2

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return Data() }
        var mediaBox = pageRect
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let titleFont = NSFont.systemFont(ofSize: 22, weight: .bold)
        let h2Font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let smallFont = NSFont.systemFont(ofSize: 9, weight: .regular)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        // 状态：在 page 内当前 y 坐标（自顶向下递减）
        var y: CGFloat = pageRect.height - margin

        func newPage() {
            ctx.endPDFPage()
            ctx.beginPDFPage(nil)
            // 还原 macOS 坐标：PDFContext 默认左下角原点，已经是我们要的
            y = pageRect.height - margin
        }

        func ensureSpace(_ need: CGFloat) {
            if y - need < margin {
                newPage()
            }
        }

        func draw(_ text: String, font: NSFont, at point: CGPoint, color: NSColor = .black) {
            let attr: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let line = NSAttributedString(string: text, attributes: attr)
            // 使用 CoreText 渲染（PDFKit 上下文里 NSAttributedString.draw 也可用）
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            line.draw(at: point)
            NSGraphicsContext.restoreGraphicsState()
        }

        /// 在 (margin, y) 位置画一段文字，并向下推进 lineHeight。
        func drawLine(_ text: String, font: NSFont, color: NSColor = .black, leftIndent: CGFloat = 0) {
            let lineHeight = font.ascender - font.descender + 4
            ensureSpace(lineHeight)
            y -= lineHeight
            draw(text, font: font, at: CGPoint(x: margin + leftIndent, y: y), color: color)
        }

        func drawHRule() {
            ensureSpace(8)
            y -= 6
            ctx.setStrokeColor(NSColor.lightGray.cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: margin, y: y))
            ctx.addLine(to: CGPoint(x: margin + contentWidth, y: y))
            ctx.strokePath()
            y -= 2
        }

        /// 简单等距列绘制（最后一列右对齐）。widths 总和应 <= contentWidth。
        func drawRow(_ cells: [String], widths: [CGFloat], font: NSFont, isHeader: Bool = false) {
            let lineHeight = font.ascender - font.descender + 4
            ensureSpace(lineHeight)
            y -= lineHeight
            var x = margin
            for (idx, cell) in cells.enumerated() {
                let w = widths[idx]
                let attr: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: isHeader ? NSColor.darkGray : NSColor.black
                ]
                let str = NSAttributedString(string: cell, attributes: attr)
                let cellRect: CGRect
                if idx == cells.count - 1 {
                    // 右对齐
                    let size = str.size()
                    cellRect = CGRect(x: x + w - size.width - 2, y: y, width: size.width, height: lineHeight)
                } else {
                    cellRect = CGRect(x: x, y: y, width: w - 4, height: lineHeight)
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                str.draw(in: cellRect)
                NSGraphicsContext.restoreGraphicsState()
                x += w
            }
        }

        // -- 开始画 --
        ctx.beginPDFPage(nil)

        // 标题
        let title = "Tokenomics · \(report.monthLabel) 月度账单"
        drawLine(title, font: titleFont)
        y -= 2
        let stampFmt = DateFormatter()
        stampFmt.dateFormat = "yyyy-MM-dd HH:mm"
        drawLine("生成时间：\(stampFmt.string(from: Date()))", font: smallFont, color: .gray)
        if let name = accountName, !name.isEmpty {
            drawLine("账户 / 团队：\(name)", font: smallFont, color: .gray)
        }
        drawHRule()

        // 合计概览
        y -= 6
        drawLine("合计", font: h2Font)
        drawLine("总花费：\(CurrencyFormatting.format(usd: report.totalCostUSD, currency: currency, usdCnyRate: rate))",
                 font: bodyFont, leftIndent: 8)
        drawLine("总 Token：\(formatInt(report.totalTokens))", font: bodyFont, leftIndent: 8)
        drawLine("记录条数：\(report.totalRecords)", font: bodyFont, leftIndent: 8)
        drawLine("当前汇率：1 USD ≈ \(String(format: "%.4f", rate)) CNY", font: smallFont, color: .gray, leftIndent: 8)

        // 按供应商
        if !report.subtotalByProvider.isEmpty {
            y -= 6
            drawLine("按供应商", font: h2Font)
            let widths: [CGFloat] = [contentWidth * 0.35, contentWidth * 0.25, contentWidth * 0.2, contentWidth * 0.2]
            drawRow(["供应商", "花费", "Token", "调用数"], widths: widths, font: bodyFont, isHeader: true)
            for p in report.subtotalByProvider {
                let cost = CurrencyFormatting.format(usd: p.costUSD, currency: currency, usdCnyRate: rate)
                drawRow([p.providerDisplay, cost, formatInt(p.tokens), "\(p.count)"],
                        widths: widths, font: monoFont)
            }
        }

        // 按模型
        if !report.lineItems.isEmpty {
            y -= 8
            drawLine("按模型", font: h2Font)
            let widths: [CGFloat] = [
                contentWidth * 0.22,  // provider
                contentWidth * 0.28,  // model
                contentWidth * 0.10,  // count
                contentWidth * 0.13,  // in
                contentWidth * 0.13,  // out
                contentWidth * 0.14   // cost
            ]
            drawRow(["供应商", "模型", "调用", "输入", "输出", "花费"],
                    widths: widths, font: bodyFont, isHeader: true)
            for it in report.lineItems {
                let cost = CurrencyFormatting.format(usd: it.costUSD, currency: currency, usdCnyRate: rate)
                drawRow([
                    it.providerDisplay,
                    it.model,
                    "\(it.count)",
                    formatInt(it.inputTokens),
                    formatInt(it.outputTokens),
                    cost
                ], widths: widths, font: monoFont)
            }
        }

        // Footer
        y = margin + 14
        draw("本账单由 Tokenomics 自动生成，仅供报销 / 内部对账参考。",
             font: smallFont,
             at: CGPoint(x: margin, y: margin), color: .gray)

        ctx.endPDFPage()
        ctx.closePDF()

        return pdfData as Data
    }

    // MARK: - 小工具

    private static func formatInt(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - 系统 I/O：保存面板 & 剪贴板

    /// 弹保存面板。`contentTypes` 可传 [.pdf] / [.json] / [.commaSeparatedText] 等。
    /// 失败 / 取消都返回 false。
    @MainActor
    @discardableResult
    static func saveWithPanel(
        suggestedName: String,
        contentTypes: [UTType],
        write: (URL) throws -> Void
    ) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = contentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try write(url)
            return true
        } catch {
            NSLog("ReportExporter save failed: \(error)")
            return false
        }
    }

    /// 拷贝纯文本到剪贴板（覆盖式）。
    @MainActor
    static func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
