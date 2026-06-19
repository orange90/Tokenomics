import Foundation

/// USD → CNY 汇率服务。优先调用 exchangerate.host，失败兜底默认值。
final class ExchangeRateService {
    private let fallbackRate: Double = 7.20
    private var cached: (rate: Double, fetchedAt: Date)?
    private let cacheTTL: TimeInterval = 3600

    func fetchUSDtoCNY(forceRefresh: Bool = false) async throws -> Double {
        if !forceRefresh, let c = cached, Date().timeIntervalSince(c.fetchedAt) < cacheTTL {
            return c.rate
        }

        let urlString = "https://api.exchangerate.host/latest?base=USD&symbols=CNY"
        guard let url = URL(string: urlString) else { return fallbackRate }

        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            struct Resp: Decodable { let rates: [String: Double]? }
            let resp = try JSONDecoder().decode(Resp.self, from: data)
            if let r = resp.rates?["CNY"], r > 0 {
                cached = (r, Date())
                return r
            }
            print("[ExchangeRateService] response missing CNY rate, using fallback")
        } catch {
            print("[ExchangeRateService] fetch failed: \(error)")
        }
        return cached?.rate ?? fallbackRate
    }

    var currentRate: Double {
        cached?.rate ?? fallbackRate
    }
}
