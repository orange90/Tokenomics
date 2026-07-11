import SwiftUI

/// Dashboard 上的"Claude 路由健康"卡片：
///   🟢 clean       近 24h 未观察到降级/异常
///   🟡 suspicious  有可疑事件（output_tokens 显著偏移、异常 stop_reason 等）
///   🔴 downgraded  明确降级（请求档位 > 返回档位）
///   ⚪ unavailable 未启用主动探测 or 未配置 canary key
struct DowngradeCard: View {
    let verdict: DowngradeVerdict
    let enabled: Bool
    let hasCanaryKey: Bool
    let lastCheckedAt: Date?
    let onTapDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.tr("downgrade.card.title"))
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 10, height: 10)
            }
            Text(statusText)
                .font(.title3.weight(.semibold))
                .foregroundStyle(indicatorColor)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(L10n.tr("downgrade.card.details")) {
                    onTapDetail()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Spacer()
                if let t = lastCheckedAt {
                    Text(String(format: L10n.tr("downgrade.card.last.fmt"), Self.timeFmt.string(from: t)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        )
    }

    private var indicatorColor: Color {
        if !enabled || !hasCanaryKey { return .secondary }
        switch verdict {
        case .clean:      return .green
        case .suspicious: return .yellow
        case .downgraded: return .red
        }
    }

    private var statusText: String {
        if !hasCanaryKey { return L10n.tr("downgrade.card.status.no_key") }
        if !enabled      { return L10n.tr("downgrade.card.status.disabled") }
        switch verdict {
        case .clean:      return L10n.tr("downgrade.card.status.clean")
        case .suspicious: return L10n.tr("downgrade.card.status.suspicious")
        case .downgraded: return L10n.tr("downgrade.card.status.downgraded")
        }
    }

    private var subtitle: String {
        if !hasCanaryKey { return L10n.tr("downgrade.card.subtitle.no_key") }
        if !enabled      { return L10n.tr("downgrade.card.subtitle.disabled") }
        switch verdict {
        case .clean:      return L10n.tr("downgrade.card.subtitle.clean")
        case .suspicious: return L10n.tr("downgrade.card.subtitle.suspicious")
        case .downgraded: return L10n.tr("downgrade.card.subtitle.downgraded")
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}

extension Notification.Name {
    /// 由 Dashboard 上的 DowngradeCard 触发，RootView 监听后切换到侧边栏「降级检测」详情页。
    static let tokenomicsOpenDowngrade = Notification.Name("tc.openDowngrade")
}
