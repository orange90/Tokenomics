import SwiftUI

struct ProviderRow: View {
    let providerKey: String
    let displayName: String
    let colorHex: String
    let totalCostUSD: Double
    let totalTokens: Int
    let recordCount: Int
    let currency: Currency
    let rate: Double

    /// 兼容旧调用：直接给一个内置 Provider 也能用。
    init(provider: Provider,
         totalCostUSD: Double,
         totalTokens: Int,
         recordCount: Int,
         currency: Currency,
         rate: Double) {
        self.providerKey = provider.rawValue
        self.displayName = provider.displayName
        self.colorHex = provider.brandColorHex
        self.totalCostUSD = totalCostUSD
        self.totalTokens = totalTokens
        self.recordCount = recordCount
        self.currency = currency
        self.rate = rate
    }

    init(providerKey: String,
         displayName: String,
         colorHex: String,
         totalCostUSD: Double,
         totalTokens: Int,
         recordCount: Int,
         currency: Currency,
         rate: Double) {
        self.providerKey = providerKey
        self.displayName = displayName
        self.colorHex = colorHex
        self.totalCostUSD = totalCostUSD
        self.totalTokens = totalTokens
        self.recordCount = recordCount
        self.currency = currency
        self.rate = rate
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body.weight(.medium))
                Text(L10n.tr("providerrow.subtitle.fmt", recordCount, totalTokens.formatted()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(CurrencyFormatting.format(usd: totalCostUSD, currency: currency, usdCnyRate: rate))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 6)
    }
}
