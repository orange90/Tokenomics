import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: SidebarItem? = .dashboard

    enum SidebarItem: Hashable, Identifiable {
        case dashboard
        case breakeven
        case provider(Provider)
        case customProvider(String)   // CustomProvider.id
        case models
        case logs

        var id: String {
            switch self {
            case .dashboard: return "dashboard"
            case .breakeven: return "breakeven"
            case .provider(let p): return "p-\(p.rawValue)"
            case .customProvider(let key): return "cp-\(key)"
            case .models: return "models"
            case .logs: return "logs"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 220)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.manualRefresh()
                } label: {
                    Label("刷新", systemImage: appState.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .disabled(appState.isRefreshing)
                .help("立即拉取所有 Collector")
            }
        }
        .navigationTitle("Token 计数器")
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("总览") {
                Label("仪表盘", systemImage: "chart.line.uptrend.xyaxis")
                    .tag(SidebarItem.dashboard)
                Label("回本没", systemImage: "figure.dance")
                    .tag(SidebarItem.breakeven)
                Label("模型分布", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.models)
                Label("拉取日志", systemImage: "doc.text")
                    .tag(SidebarItem.logs)
            }
            Section("供应商") {
                ForEach(Provider.allCases.filter { $0 != .unknown && !appState.isProviderHidden($0.rawValue) }) { p in
                    Label {
                        Text(p.displayName)
                    } icon: {
                        Circle().fill(Color(hex: p.brandColorHex)).frame(width: 10, height: 10)
                    }
                    .tag(SidebarItem.provider(p))
                }
                ForEach(appState.customProviders.filter { !appState.isProviderHidden($0.id) }) { cp in
                    Label {
                        Text(cp.name)
                    } icon: {
                        Circle().fill(Color(hex: cp.colorHex)).frame(width: 10, height: 10)
                    }
                    .tag(SidebarItem.customProvider(cp.id))
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .dashboard {
        case .dashboard:
            DashboardView()
        case .breakeven:
            BreakevenView()
        case .provider(let p):
            ProviderDetailView(provider: p)
        case .customProvider(let key):
            if let cp = appState.customProviders.first(where: { $0.id == key }) {
                ProviderDetailView(customProviderKey: cp.id, displayName: cp.name, colorHex: cp.colorHex)
            } else {
                ContentUnavailableView("供应商不存在", systemImage: "questionmark.circle")
            }
        case .models:
            ModelBreakdownView()
        case .logs:
            LogsView()
        }
    }
}

struct LogsView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("拉取日志").font(.title2.bold())
                Spacer()
                Button("清空") { appState.statusMessages.removeAll() }
            }.padding()
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(appState.statusMessages.enumerated()), id: \.offset) { _, msg in
                        Text(msg)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
        }
    }
}
