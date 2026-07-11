import SwiftUI

/// Dashboard 上的 "Claude Desktop 隐写术 / 浏览器注入" 检测卡片。
///
///   🟢 clean       未观测到浏览器注入产物、也未观测到隐写字符
///   🟡 suspicious  有可疑迹象（浏览器 profile 关键字命中 / 未知非 ASCII 字符）
///   🔴 confirmed   捕获到爆料中列出的 Unicode 码位
///   ⚪ 未扫描      从未扫描过
struct StegoDetectionCard: View {
    let report: StegoReport?
    let isScanning: Bool
    let progress: Double
    let onScanNow: () -> Void
    let onTapDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.tr("stego.card.title"))
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 10, height: 10)
            }

            Text(statusText)
                .font(.title3.weight(.semibold))
                .foregroundStyle(indicatorColor)

            Text(subtitleText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isScanning {
                ProgressView(value: max(0, min(progress, 1)))
                    .progressViewStyle(.linear)
            }

            HStack {
                Button {
                    onScanNow()
                } label: {
                    Label(L10n.tr("stego.card.scan_now"), systemImage: "magnifyingglass")
                }
                .disabled(isScanning)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(L10n.tr("stego.card.details")) {
                    onTapDetail()
                }
                .controlSize(.small)

                Spacer()
                if let t = report?.generatedAt {
                    Text(String(format: L10n.tr("stego.card.last.fmt"), Self.timeFmt.string(from: t)))
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
        guard let r = report else { return .secondary }
        switch r.severity {
        case .clean:      return .green
        case .suspicious: return .yellow
        case .confirmed:  return .red
        }
    }

    private var statusText: String {
        guard let r = report else { return L10n.tr("stego.card.status.unknown") }
        switch r.severity {
        case .clean:      return L10n.tr("stego.card.status.clean")
        case .suspicious: return L10n.tr("stego.card.status.suspicious")
        case .confirmed:  return L10n.tr("stego.card.status.confirmed")
        }
    }

    private var subtitleText: String {
        guard let r = report else { return L10n.tr("stego.card.subtitle.never") }
        switch r.severity {
        case .clean:      return L10n.tr("stego.card.subtitle.clean")
        case .suspicious: return String(format: L10n.tr("stego.card.subtitle.suspicious.fmt"),
                                        r.browserHits.count, r.promptHits.count)
        case .confirmed:  return String(format: L10n.tr("stego.card.subtitle.confirmed.fmt"),
                                        r.promptHits.count, r.browserHits.count)
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}

extension Notification.Name {
    /// Dashboard 上的 StegoDetectionCard 触发，RootView 监听后切到侧边栏「隐写术检测」。
    static let tokenomicsOpenStego = Notification.Name("tc.openStego")
}
