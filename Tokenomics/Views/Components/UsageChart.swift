import SwiftUI
import Charts

struct DailyCost: Identifiable {
    let id = UUID()
    let day: Date
    let provider: String
    let costUSD: Double
}

struct UsageTrendChart: View {
    let data: [DailyCost]
    let rate: Double
    let currency: Currency

    var body: some View {
        Chart(data) { item in
            BarMark(
                x: .value("日期", item.day, unit: .day),
                y: .value("花费 USD", item.costUSD)
            )
            .foregroundStyle(by: .value("供应商", item.provider))
            .cornerRadius(3)
        }
        .chartLegend(position: .bottom, alignment: .center, spacing: 12)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { v in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let usd = value.as(Double.self) {
                        Text(CurrencyFormatting.format(usd: usd, currency: currency, usdCnyRate: rate))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(minHeight: 240)
    }
}
