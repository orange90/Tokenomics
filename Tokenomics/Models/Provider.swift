import Foundation

enum Provider: String, CaseIterable, Identifiable, Codable {
    case anthropic
    case openai
    case google
    case deepseek
    case qwen
    case qwenIntl
    case siliconflow
    case openrouter
    case stepfun
    case mimo
    case kimi
    case glm
    case minimax
    case cursor
    case traeSolo
    case qoder
    case volcengine
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic:   return L10n.tr("provider.anthropic")
        case .openai:      return L10n.tr("provider.openai")
        case .google:      return L10n.tr("provider.google")
        case .deepseek:    return L10n.tr("provider.deepseek")
        case .qwen:        return L10n.tr("provider.qwen")
        case .qwenIntl:    return L10n.tr("provider.qwenIntl")
        case .siliconflow: return L10n.tr("provider.siliconflow")
        case .openrouter:  return L10n.tr("provider.openrouter")
        case .stepfun:     return L10n.tr("provider.stepfun")
        case .mimo:        return L10n.tr("provider.mimo")
        case .kimi:        return L10n.tr("provider.kimi")
        case .glm:         return L10n.tr("provider.glm")
        case .minimax:     return L10n.tr("provider.minimax")
        case .cursor:      return L10n.tr("provider.cursor")
        case .traeSolo:    return L10n.tr("provider.traeSolo")
        case .qoder:       return L10n.tr("provider.qoder")
        case .volcengine:  return L10n.tr("provider.volcengine")
        case .unknown:     return L10n.tr("provider.unknown")
        }
    }

    var brandColorHex: String {
        switch self {
        case .anthropic:   return "#C9A37A"
        case .openai:      return "#10A37F"
        case .google:      return "#4285F4"
        case .deepseek:    return "#1A73E8"
        case .qwen:        return "#7C3AED"
        case .qwenIntl:    return "#A78BFA"
        case .siliconflow: return "#0EA5E9"
        case .openrouter:  return "#F97316"
        case .stepfun:     return "#2563EB"
        case .mimo:        return "#FF6900"
        case .kimi:        return "#111827"
        case .glm:         return "#3B82F6"
        case .minimax:     return "#0EAA73"
        case .cursor:      return "#1F1F1F"
        case .traeSolo:    return "#FF4B59"
        case .qoder:       return "#22C55E"
        case .volcengine:  return "#EF4444"
        case .unknown:     return "#9CA3AF"
        }
    }
}
