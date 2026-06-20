import SwiftUI

/// 一个 Plan 在三个时间窗口下的真实用量（按 UsageRecord 聚合）。
struct PlanUsageStats: Equatable {
    let todayCostUSD: Double
    let todayTokens: Int
    let weekCostUSD: Double
    let weekTokens: Int
    let monthCostUSD: Double
    let monthTokens: Int

    static let zero = PlanUsageStats(
        todayCostUSD: 0, todayTokens: 0,
        weekCostUSD: 0, weekTokens: 0,
        monthCostUSD: 0, monthTokens: 0
    )
}

/// 展示单个供应商（Claude / Codex）的订阅额度：5h 窗口、每周窗口等多个进度条。
struct QuotaCard: View {
    let snapshot: QuotaSnapshot
    let accent: Color
    let usage: PlanUsageStats
    let currency: Currency
    let usdCnyRate: Double

    init(
        snapshot: QuotaSnapshot,
        accent: Color,
        usage: PlanUsageStats = .zero,
        currency: Currency = .usd,
        usdCnyRate: Double = 1.0
    ) {
        self.snapshot = snapshot
        self.accent = accent
        self.usage = usage
        self.currency = currency
        self.usdCnyRate = usdCnyRate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.providerName)
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
            }

            if let acct = snapshot.accountIdentifier {
                Text(acct)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(alignment: .leading, spacing: 8) {
                if snapshot.windows.isEmpty {
                    Text(L10n.tr("quotacard.empty"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(snapshot.windows) { w in
                    QuotaWindowRow(window: w, accent: accent)
                }
            }

            usageSection

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(L10n.tr("quotacard.updated.fmt", Self.timeFmt.string(from: snapshot.fetchedAt), snapshot.source))
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("quotacard.usage.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 8) {
                usageCell(
                    title: L10n.tr("quotacard.usage.today"),
                    cost: usage.todayCostUSD,
                    tokens: usage.todayTokens
                )
                Divider().frame(height: 36)
                usageCell(
                    title: L10n.tr("quotacard.usage.week"),
                    cost: usage.weekCostUSD,
                    tokens: usage.weekTokens
                )
                Divider().frame(height: 36)
                usageCell(
                    title: L10n.tr("quotacard.usage.month"),
                    cost: usage.monthCostUSD,
                    tokens: usage.monthTokens
                )
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func usageCell(title: String, cost: Double, tokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(CurrencyFormatting.format(usd: cost, currency: currency, usdCnyRate: usdCnyRate))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(accent)
            Text(L10n.tr("quotacard.usage.tokens.fmt", Self.tokensFmt(tokens)))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func tokensFmt(_ n: Int) -> String {
        let v = Double(n)
        switch v {
        case 1_000_000...:
            return String(format: "%.2fM", v / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", v / 1_000)
        default:
            return "\(n)"
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

private struct QuotaWindowRow: View {
    let window: QuotaWindow
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(titleLabel)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(barColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(2, geo.size.width * CGFloat(min(1, max(0, window.usedPercent / 100)))))
                }
            }
            .frame(height: 6)
            if let resetAt = window.resetsAt {
                Text(L10n.tr("quotacard.reset.fmt", Self.relativeFmt.localizedString(for: resetAt, relativeTo: Date())))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var titleLabel: String {
        if let note = window.note { return "\(window.title) · \(note)" }
        return window.title
    }

    private var barColor: Color {
        switch window.usedPercent {
        case ..<60: return accent
        case ..<85: return .orange
        default:    return .red
        }
    }

    private static let relativeFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
