import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var localization: LocalizationManager
    @State private var selection: SidebarItem? = .breakeven

    enum SidebarItem: Hashable, Identifiable {
        case dashboard
        case breakeven
        case provider(Provider)
        case customProvider(String)
        case models
        case tasks
        case logs

        var id: String {
            switch self {
            case .dashboard: return "dashboard"
            case .breakeven: return "breakeven"
            case .provider(let p): return "p-\(p.rawValue)"
            case .customProvider(let key): return "cp-\(key)"
            case .models: return "models"
            case .tasks: return "tasks"
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
                    Label(L10n.tr("toolbar.refresh"), systemImage: appState.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .disabled(appState.isRefreshing)
                .help(L10n.tr("toolbar.refresh.help"))
            }
        }
        .navigationTitle(L10n.tr("app.title"))
        .id(localization.language.rawValue)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section(L10n.tr("sidebar.section.overview")) {
                Label(L10n.tr("sidebar.breakeven"), systemImage: "figure.dance")
                    .tag(SidebarItem.breakeven)
                Label(L10n.tr("sidebar.dashboard"), systemImage: "chart.line.uptrend.xyaxis")
                    .tag(SidebarItem.dashboard)
                Label(L10n.tr("sidebar.models"), systemImage: "square.grid.2x2")
                    .tag(SidebarItem.models)
                Label(L10n.tr("sidebar.tasks"), systemImage: "checklist")
                    .tag(SidebarItem.tasks)
                Label(L10n.tr("sidebar.logs"), systemImage: "doc.text")
                    .tag(SidebarItem.logs)
            }
            Section(L10n.tr("sidebar.section.providers")) {
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
        switch selection ?? .breakeven {
        case .dashboard:
            DashboardView()
        case .breakeven:
            BreakevenView(onShowModels: { selection = .models })
        case .provider(let p):
            ProviderDetailView(provider: p)
        case .customProvider(let key):
            if let cp = appState.customProviders.first(where: { $0.id == key }) {
                ProviderDetailView(customProviderKey: cp.id, displayName: cp.name, colorHex: cp.colorHex)
            } else {
                ContentUnavailableView(L10n.tr("common.provider_not_exist"), systemImage: "questionmark.circle")
            }
        case .models:
            ModelBreakdownView()
        case .tasks:
            TasksView()
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
                Text(L10n.tr("logs.title")).font(.title2.bold())
                Spacer()
                Button(L10n.tr("logs.clear")) { appState.statusMessages.removeAll() }
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
