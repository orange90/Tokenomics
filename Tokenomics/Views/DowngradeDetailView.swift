import SwiftUI
import SwiftData

/// 详情页：Claude 降级检测事件时间线。
///
/// 展示：
///   - 顶部健康度总结（近 24h）
///   - 全部事件列表（按时间倒序），每条含：时间 / 结果 / 请求 vs 服务的模型 / 摘要 / 详细 JSON
struct DowngradeDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var localization: LocalizationManager
    @Query(sort: \DowngradeSignal.timestamp, order: .reverse) private var signals: [DowngradeSignal]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if signals.isEmpty {
                empty
            } else {
                list
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .id(localization.language.rawValue)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.tr("downgrade.detail.title"))
                    .font(.title2.bold())
                Spacer()
                Button {
                    appState.runDowngradeProbeNow()
                } label: {
                    Label(L10n.tr("downgrade.detail.run_now"), systemImage: "play.circle")
                }
                .disabled(!appState.downgradeProbeEnabled)
            }

            HStack(spacing: 12) {
                Circle()
                    .fill(healthColor)
                    .frame(width: 10, height: 10)
                Text(healthText).font(.callout.weight(.medium))
                Spacer()
                Text(L10n.tr("downgrade.detail.total.fmt", signals.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(L10n.tr("downgrade.detail.disclaimer"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private var empty: some View {
        ContentUnavailableView(
            L10n.tr("downgrade.detail.empty.title"),
            systemImage: "shield",
            description: Text(L10n.tr("downgrade.detail.empty.desc"))
        )
        .padding()
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(signals) { s in
                    SignalRow(signal: s)
                    Divider()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var healthColor: Color {
        switch appState.downgradeHealth {
        case .clean:      return .green
        case .suspicious: return .yellow
        case .downgraded: return .red
        }
    }

    private var healthText: String {
        switch appState.downgradeHealth {
        case .clean:      return L10n.tr("downgrade.card.status.clean")
        case .suspicious: return L10n.tr("downgrade.card.status.suspicious")
        case .downgraded: return L10n.tr("downgrade.card.status.downgraded")
        }
    }
}

private struct SignalRow: View {
    let signal: DowngradeSignal
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(signal.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(sourceLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(verdictLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(dotColor)
            }
            HStack(spacing: 6) {
                Text(signal.requestedModel).font(.callout.weight(.medium))
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                Text(signal.servedModel).font(.callout.weight(.medium))
                    .foregroundStyle(signal.servedModel == signal.requestedModel ? .primary : dotColor)
            }
            Text(signal.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup(isExpanded: $expanded) {
                Text(prettyJSON(signal.detailsJSON))
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } label: {
                Text(L10n.tr("downgrade.detail.row.raw"))
                    .font(.caption)
            }
        }
        .padding(.vertical, 10)
    }

    private var dotColor: Color {
        switch signal.verdict {
        case .clean:      return .green
        case .suspicious: return .yellow
        case .downgraded: return .red
        }
    }

    private var verdictLabel: String {
        switch signal.verdict {
        case .clean:      return L10n.tr("downgrade.card.status.clean")
        case .suspicious: return L10n.tr("downgrade.card.status.suspicious")
        case .downgraded: return L10n.tr("downgrade.card.status.downgraded")
        }
    }

    private var sourceLabel: String {
        switch signal.source {
        case .activeCanary: return L10n.tr("downgrade.source.canary")
        case .passiveLog:   return L10n.tr("downgrade.source.passive")
        }
    }

    private func prettyJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: pretty, encoding: .utf8) else {
            return raw
        }
        return s
    }
}
