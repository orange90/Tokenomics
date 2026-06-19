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
        case .anthropic:   return "Anthropic"
        case .openai:      return "OpenAI"
        case .google:      return "Google Gemini"
        case .deepseek:    return "DeepSeek"
        case .qwen:        return "通义千问 (国内)"
        case .qwenIntl:    return "Qwen (International)"
        case .siliconflow: return "硅基流动"
        case .openrouter:  return "OpenRouter"
        case .stepfun:     return "阶跃星辰 (Stepfun)"
        case .mimo:        return "小米 MiMo"
        case .kimi:        return "Kimi (Moonshot)"
        case .glm:         return "智谱 GLM"
        case .minimax:     return "MiniMax (海螺)"
        case .cursor:      return "Cursor"
        case .traeSolo:    return "TRAE Solo"
        case .qoder:       return "Qoder"
        case .volcengine:  return "火山方舟 (豆包)"
        case .unknown:     return "未知"
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
