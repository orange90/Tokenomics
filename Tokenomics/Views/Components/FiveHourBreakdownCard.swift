import SwiftUI

/// Dashboard 顶部的「5 小时限额」卡片。
///
/// - 顶部两个可点击的「框框」：OpenAI / Anthropic。
/// - 点中其中一个后，下面展示该 provider 当前 5h 窗口的总使用率
///   以及窗口内今日每个任务（来自 TasksScanner 的 TaskSession）所占的百分比。
///
/// 百分比换算原则：与 Tasks 详情页保持一致 —— 由于额度接口只回 utilization%，
/// 我们用「窗口内所有任务的 token 总和」反推每 token 的额度权重，再按任务自身 token 数加权。
/// 这样所有任务的份额加起来约等于 window.usedPercent。
struct FiveHourBreakdownCard: View {
    let snapshot: QuotaSnapshot?
    let selectedProvider: Provider
    let sessionsToday: [TaskSession]
    let onSelectProvider: (Provider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            providerChips
            divider
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.secondary.opacity(0.2))
                )
        )
    }

    // MARK: - Provider chips (the two top "boxes")

    private var providerChips: some View {
        HStack(spacing: 12) {
            providerChip(.openai)
            providerChip(.anthropic)
        }
    }

    private func providerChip(_ p: Provider) -> some View {
        let color = Color(hex: p.brandColorHex)
        let selected = p == selectedProvider
        return Button {
            onSelectProvider(p)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.displayName)
                        .font(.headline)
                    Text(L10n.tr("dashboard.five_hour.section"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? color.opacity(0.18) : Color.secondary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? color : Color.secondary.opacity(0.25),
                                          lineWidth: selected ? 1.5 : 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(height: 1)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let accent = Color(hex: selectedProvider.brandColorHex)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(selectedProvider.displayName) · \(L10n.tr("dashboard.five_hour.section"))")
                    .font(.headline)
                Spacer()
                if let w = window {
                    Text("\(Int(w.usedPercent.rounded()))%")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(barColor(w.usedPercent, accent: accent))
                }
            }

            if let w = window {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor(w.usedPercent, accent: accent))
                            .frame(width: max(2, geo.size.width * CGFloat(min(1, max(0, w.usedPercent / 100)))))
                    }
                }
                .frame(height: 8)

                HStack(spacing: 12) {
                    Text(L10n.tr("dashboard.five_hour.window_used.fmt",
                                 Self.percentFmt(w.usedPercent)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let resets = w.resetsAt {
                        Text(L10n.tr("dashboard.five_hour.window_resets.fmt",
                                     Self.relativeFmt.localizedString(for: resets, relativeTo: Date())))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(L10n.tr("dashboard.five_hour.no_snapshot"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(L10n.tr("dashboard.five_hour.pick_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)

            taskBreakdown(accent: accent)
        }
    }

    // MARK: - Task breakdown table

    @ViewBuilder
    private func taskBreakdown(accent: Color) -> some View {
        let rows = breakdownRows
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("dashboard.five_hour.by_task"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text(L10n.tr("dashboard.five_hour.empty_tasks"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                headerRow
                Divider()
                ForEach(rows) { r in
                    row(r, accent: accent)
                    Divider()
                }
                summaryLine(rows: rows)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private var headerRow: some View {
        HStack {
            Text(L10n.tr("dashboard.five_hour.col.task"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.tr("dashboard.five_hour.col.project"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.tr("dashboard.five_hour.col.time"))
                .frame(width: 110, alignment: .trailing)
            Text(L10n.tr("dashboard.five_hour.col.tokens"))
                .frame(width: 90, alignment: .trailing)
            Text(L10n.tr("dashboard.five_hour.col.share"))
                .frame(width: 100, alignment: .trailing)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
    }

    private func row(_ r: BreakdownRow, accent: Color) -> some View {
        HStack {
            Text(r.shortID)
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(r.project)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(Self.relativeFmt.localizedString(for: r.time, relativeTo: Date()))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
                .monospacedDigit()
            Text(Self.tokensShort(r.tokens))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
                .monospacedDigit()
            Text(Self.percentFmt(r.sharePercent))
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 100, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private func summaryLine(rows: [BreakdownRow]) -> some View {
        let totalTokens = rows.reduce(0) { $0 + $1.tokens }
        let totalShare = rows.reduce(0.0) { $0 + $1.sharePercent }
        return Text(L10n.tr(
            "dashboard.five_hour.total.fmt",
            rows.count,
            Self.tokensShort(totalTokens),
            Self.percentFmt(totalShare)
        ))
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    // MARK: - Derived data

    private var window: QuotaWindow? {
        snapshot?.windows.first { $0.id == "five_hour" }
    }

    /// 当前 5h 窗口的开始时间。仅当 snapshot 含 `resetsAt` 时才能反推。
    private var windowRange: (start: Date, end: Date)? {
        guard let w = window, let resets = w.resetsAt else { return nil }
        let start = resets.addingTimeInterval(-5 * 3600)
        return (start, resets)
    }

    /// 窗口内、属于今日（startOfDay 以后）的会话；按时间逆序展示。
    private var sessionsInWindow: [TaskSession] {
        guard let range = windowRange else { return [] }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let lowerBound = max(range.start, startOfToday)
        return sessionsToday.filter { s in
            guard let ts = s.lastTimestamp else { return false }
            return ts >= lowerBound && ts <= range.end
        }
        .sorted { ($0.lastTimestamp ?? .distantPast) > ($1.lastTimestamp ?? .distantPast) }
    }

    private var breakdownRows: [BreakdownRow] {
        guard let w = window else { return [] }
        let inWindow = sessionsInWindow
        let totalTokens = inWindow.reduce(0) { $0 + $1.totalTokens }
        guard totalTokens > 0 else { return [] }
        return inWindow.compactMap { s -> BreakdownRow? in
            guard let ts = s.lastTimestamp, s.totalTokens > 0 else { return nil }
            let share = Double(s.totalTokens) / Double(totalTokens) * w.usedPercent
            return BreakdownRow(
                id: s.id,
                shortID: s.shortID,
                project: prettyProjectName(s.projectDir),
                time: ts,
                tokens: s.totalTokens,
                sharePercent: share
            )
        }
    }

    private func prettyProjectName(_ raw: String) -> String {
        if !raw.hasPrefix("-") { return raw }
        let parts = raw.split(separator: "-").map(String.init).filter { !$0.isEmpty }
        return parts.last ?? raw
    }

    private func barColor(_ percent: Double, accent: Color) -> Color {
        switch percent {
        case ..<60: return accent
        case ..<85: return .orange
        default:    return .red
        }
    }

    // MARK: - Formatters

    fileprivate struct BreakdownRow: Identifiable {
        let id: String
        let shortID: String
        let project: String
        let time: Date
        let tokens: Int
        let sharePercent: Double
    }

    private static func tokensShort(_ n: Int) -> String {
        let v = Double(n)
        switch v {
        case 1_000_000...: return String(format: "%.2fM", v / 1_000_000)
        case 1_000...:     return String(format: "%.1fK", v / 1_000)
        default:           return "\(n)"
        }
    }

    private static func percentFmt(_ v: Double) -> String {
        if v >= 10 { return String(format: "%.0f%%", v) }
        if v >= 1  { return String(format: "%.1f%%", v) }
        return String(format: "%.2f%%", v)
    }

    private static let relativeFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
