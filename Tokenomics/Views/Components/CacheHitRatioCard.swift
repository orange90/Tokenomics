import SwiftUI

/// 显示 Prompt Caching 命中率：cacheRead / (input + cacheRead + cacheWrite)。
/// 这是 Claude / OpenAI prompt caching 用户最关心的成本指标 —— 命中率越高，
/// 同样体量的输入 token 实付费用越低。output 不参与分母。
struct CacheHitRatioCard: View {
    let title: String
    /// 0...1 之间；nil 表示样本量不足，展示占位文字。
    let ratio: Double?
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let inputTokens: Int
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(ratioText)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ratio == nil ? .secondary : .primary)

            ratioBar

            HStack(spacing: 4) {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.caption2)
                Text(L10n.tr(
                    "cache_hit.breakdown.fmt",
                    cacheReadTokens.formatted(),
                    cacheWriteTokens.formatted(),
                    inputTokens.formatted()
                ))
                .font(.caption)
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
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
                .padding(12)
        }
    }

    private var ratioText: String {
        guard let r = ratio else { return L10n.tr("cache_hit.no_data") }
        return String(format: "%.1f%%", r * 100)
    }

    @ViewBuilder
    private var ratioBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(accent.opacity(0.15))
                Capsule()
                    .fill(accent)
                    .frame(width: max(0, min(1, ratio ?? 0)) * proxy.size.width)
            }
        }
        .frame(height: 6)
    }
}
