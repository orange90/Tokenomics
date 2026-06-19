import SwiftUI

/// 展示单个供应商（Claude / Codex）的订阅额度：5h 窗口、每周窗口等多个进度条。
struct QuotaCard: View {
    let snapshot: QuotaSnapshot
    let accent: Color

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
                    Text("无可显示的额度窗口")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(snapshot.windows) { w in
                    QuotaWindowRow(window: w, accent: accent)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text("更新于 \(Self.timeFmt.string(from: snapshot.fetchedAt)) · \(snapshot.source)")
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
                Text("将于 \(Self.relativeFmt.localizedString(for: resetAt, relativeTo: Date())) 重置")
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
