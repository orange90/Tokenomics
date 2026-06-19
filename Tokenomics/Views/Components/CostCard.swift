import SwiftUI

struct CostCard: View {
    let title: String
    let costUSD: Double
    let totalTokens: Int
    let currency: Currency
    let rate: Double
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(CurrencyFormatting.format(usd: costUSD, currency: currency, usdCnyRate: rate))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 4) {
                Image(systemName: "circle.hexagongrid")
                    .font(.caption2)
                Text("\(totalTokens.formatted()) tokens")
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
}
