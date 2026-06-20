import Foundation

enum Provider: String, CaseIterable, Identifiable, Codable {
    case anthropic
    case openai
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic:   return L10n.tr("provider.anthropic")
        case .openai:      return L10n.tr("provider.openai")
        case .unknown:     return L10n.tr("provider.unknown")
        }
    }

    var brandColorHex: String {
        switch self {
        case .anthropic:   return "#C9A37A"
        case .openai:      return "#10A37F"
        case .unknown:     return "#9CA3AF"
        }
    }
}
