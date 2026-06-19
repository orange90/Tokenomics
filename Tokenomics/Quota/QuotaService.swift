import Foundation

/// 并发拉取所有 QuotaProbe，把结果汇总成 [id: QuotaSnapshot]。
final class QuotaService {
    private let probes: [QuotaProbe]

    init(probes: [QuotaProbe]) {
        self.probes = probes
    }

    /// 便利构造器：根据 Claude 采集偏好决定 Claude probe 的组合方式（OAuth + 浏览器 Cookie）。
    /// `claudePreferences` 是闭包，便于在用户改设置时实时生效（不必重建整个 QuotaService）。
    convenience init(claudePreferences: @escaping () -> ClaudeQuotaPreferences = { .default }) {
        self.init(probes: [
            ClaudeCompositeQuotaProbe(preferences: claudePreferences),
            CodexQuotaProbe()
        ])
    }

    var availableProbes: [QuotaProbe] { probes.filter { $0.isAvailable } }

    struct FetchResult {
        var snapshots: [String: QuotaSnapshot] = [:]
        var errors: [String: Error] = [:]
    }

    func fetchAll() async -> FetchResult {
        await withTaskGroup(of: (String, Result<QuotaSnapshot, Error>).self) { group in
            for probe in probes where probe.isAvailable {
                group.addTask {
                    do {
                        let snap = try await probe.fetch()
                        return (probe.id, .success(snap))
                    } catch {
                        return (probe.id, .failure(error))
                    }
                }
            }
            var result = FetchResult()
            for await (pid, outcome) in group {
                switch outcome {
                case .success(let snap): result.snapshots[pid] = snap
                case .failure(let err):  result.errors[pid]    = err
                }
            }
            return result
        }
    }
}
