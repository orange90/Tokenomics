import Foundation

/// 各 API Collector 共享的 HTTP 调用助手。
enum APIClient {
    static func get(url: URL, headers: [String: String] = [:], timeout: TimeInterval = 15) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    static func post(url: URL, body: Data, headers: [String: String] = [:], timeout: TimeInterval = 15) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}

enum APIError: LocalizedError {
    case missingKey
    case httpStatus(Int, String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "API Key 未配置"
        case .httpStatus(let c, let m): return "HTTP \(c): \(m)"
        case .parse(let m): return "解析失败: \(m)"
        }
    }
}

/// 通用日期解析
enum DateParsing {
    static func parse(_ raw: Any?) -> Date {
        if let n = raw as? Double { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        if let n = raw as? Int    { return Date(timeIntervalSince1970: TimeInterval(n)) }
        if let s = raw as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            if let d = ISO8601DateFormatter().date(from: s) { return d }
        }
        return Date()
    }
}
