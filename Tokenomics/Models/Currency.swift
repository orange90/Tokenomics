import Foundation

enum Currency: String, CaseIterable, Identifiable, Codable {
    case usd, cny, both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usd:  return L10n.tr("currency.usd")
        case .cny:  return L10n.tr("currency.cny")
        case .both: return L10n.tr("currency.both")
        }
    }

    var symbol: String {
        switch self {
        case .usd:  return "$"
        case .cny:  return "¥"
        case .both: return "$/¥"
        }
    }
}

struct CurrencyFormatting {
    static func format(usd: Double, currency: Currency, usdCnyRate: Double) -> String {
        switch currency {
        case .usd:
            return String(format: "$%.4f", usd)
        case .cny:
            return String(format: "¥%.2f", usd * usdCnyRate)
        case .both:
            return String(format: "$%.4f / ¥%.2f", usd, usd * usdCnyRate)
        }
    }
}
