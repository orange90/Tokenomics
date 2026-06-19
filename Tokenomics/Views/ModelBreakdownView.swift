import SwiftUI
import SwiftData
import Charts

struct ModelBreakdownView: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \UsageRecord.timestamp, order: .reverse) private var records: [UsageRecord]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("模型分布").font(.title.bold())
                if records.isEmpty {
                    ContentUnavailableView("暂无数据", systemImage: "chart.pie")
                } else {
                    pieChart
                    table
                }
            }
            .padding(20)
        }
    }

    private struct Row: Identifiable {
        var id: String { model }
        let provider: String
        let model: String
        let cost: Double
        let tokens: Int
    }

    private var rows: [Row] {
        Dictionary(grouping: records) { "\($0.provider):\($0.model)" }
            .map { key, recs -> Row in
                let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
                return Row(
                    provider: parts.first ?? "",
                    model: parts.count > 1 ? parts[1] : "",
                    cost: recs.reduce(0) { $0 + $1.costUSD },
                    tokens: recs.reduce(0) { $0 + $1.totalTokens }
                )
            }
            .sorted { $0.cost > $1.cost }
    }

    private var pieChart: some View {
        Chart(rows.prefix(8).map { $0 }) { row in
            SectorMark(
                angle: .value("花费", row.cost),
                innerRadius: .ratio(0.55),
                angularInset: 1
            )
            .cornerRadius(4)
            .foregroundStyle(by: .value("模型", row.model))
        }
        .frame(height: 260)
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack {
                Text("模型").font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading)
                Text("供应商").font(.caption.bold()).frame(width: 140, alignment: .leading)
                Text("Token").font(.caption.bold()).frame(width: 140, alignment: .trailing)
                Text("花费").font(.caption.bold()).frame(width: 180, alignment: .trailing)
            }
            .padding(.vertical, 6)
            Divider()
            ForEach(rows) { r in
                HStack {
                    Text(r.model).font(.body.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Provider(rawValue: r.provider)?.displayName ?? r.provider)
                        .frame(width: 140, alignment: .leading).foregroundStyle(.secondary)
                    Text(r.tokens.formatted()).frame(width: 140, alignment: .trailing).foregroundStyle(.secondary).monospacedDigit()
                    Text(CurrencyFormatting.format(usd: r.cost, currency: appState.currency, usdCnyRate: appState.usdCnyRate))
                        .frame(width: 180, alignment: .trailing)
                        .monospacedDigit().font(.callout.weight(.medium))
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator)))
    }
}
