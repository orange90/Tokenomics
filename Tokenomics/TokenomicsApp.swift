import SwiftUI
import SwiftData

@main
struct TokenomicsApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var localization = LocalizationManager.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UsageRecord.self,
            CollectorState.self,
            PricingOverride.self,
            CustomProvider.self,
            DowngradeSignal.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(localization)
                .frame(minWidth: 980, minHeight: 640)
                .preferredColorScheme(appState.appearance.colorScheme)
                .id(localization.language.rawValue)
                .task {
                    await appState.bootstrap(modelContext: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(localization)
                .modelContainer(sharedModelContainer)
                .preferredColorScheme(appState.appearance.colorScheme)
                .id(localization.language.rawValue)
        }
    }
}
