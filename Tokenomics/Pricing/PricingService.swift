import Foundation

/// 计价服务：从内置 JSON 加载单价表，支持用户单价覆盖。
final class PricingService {
    private var table: [String: ModelPricing] = [:]    // key: "provider:model"
    private var overrides: [String: ModelPricing] = [:]
    private var missingPricingLogged: Set<String> = []

    /// 每次 builtin / overrides 重新加载后递增；供 SwiftUI View 通过 @State 重新计算用。
    private(set) var revision: Int = 0

    /// builtin 表是否已成功加载至少一次（用于 UI 兜底判断）。
    var isBuiltinLoaded: Bool { !table.isEmpty }

    @discardableResult
    func loadBuiltinTable() -> Bool {
        guard let url = Bundle.main.url(forResource: "PricingTable", withExtension: "json") else {
            print("[PricingService] PricingTable.json not found in bundle")
            return false
        }
        do {
            let data = try Data(contentsOf: url)
            let parsed = try JSONDecoder().decode(PricingTable.self, from: data)
            var dict: [String: ModelPricing] = [:]
            for entry in parsed.entries {
                dict[entry.key] = entry
            }
            self.table = dict
            self.revision &+= 1
            self.missingPricingLogged.removeAll()
            print("[PricingService] Loaded builtin pricing entries: \(dict.count) (updatedAt=\(parsed.updatedAt))")
            return true
        } catch {
            print("[PricingService] Failed to decode PricingTable.json: \(error)")
            return false
        }
    }

    @MainActor
    func loadOverrides(from repo: UsageRepository) {
        let list = repo.fetchAllPricingOverrides()
        var dict: [String: ModelPricing] = [:]
        for o in list {
            let parts = o.key.split(separator: ":", maxSplits: 1).map(String.init)
            let provider = parts.first ?? "unknown"
            let model = parts.count > 1 ? parts[1] : "unknown"
            dict[o.key] = ModelPricing(
                provider: provider,
                model: model,
                inputPer1M: o.inputPer1M,
                outputPer1M: o.outputPer1M,
                cacheWritePer1M: o.cacheWritePer1M,
                cacheReadPer1M: o.cacheReadPer1M
            )
        }
        self.overrides = dict
        self.revision &+= 1
        self.missingPricingLogged.removeAll()
    }

    func pricing(for provider: String, model: String) -> ModelPricing? {
        let key = "\(provider):\(model)"
        if let o = overrides[key] { return o }
        if let p = table[key] { return p }
        // fuzzy: 按 provider 找前缀匹配
        if let fuzzy = table.first(where: { $0.key.hasPrefix("\(provider):") && model.lowercased().contains($0.value.model.lowercased()) })?.value {
            return fuzzy
        }
        return nil
    }

    func cost(provider: String, model: String, input: Int, output: Int, cacheCreation: Int = 0, cacheCreation1h: Int = 0, cacheRead: Int = 0) -> Double {
        guard let p = pricing(for: provider, model: model) else {
            if input > 0 || output > 0 || cacheCreation > 0 || cacheRead > 0 {
                let key = "\(provider):\(model)"
                if missingPricingLogged.insert(key).inserted {
                    print("[PricingService] No pricing entry for \(key); cost treated as 0")
                }
            }
            return 0
        }
        return p.cost(inputTokens: input, outputTokens: output, cacheCreation: cacheCreation, cacheCreation1h: cacheCreation1h, cacheRead: cacheRead)
    }

    var allEntries: [ModelPricing] {
        table.values.sorted { $0.key < $1.key }
    }
}
