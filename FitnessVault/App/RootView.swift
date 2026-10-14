import SwiftUI

enum AppTab: Hashable {
    case home, activity, meals, vault
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = .home
    @State private var showingSettings = false

    var body: some View {
        TabView(selection: $selection) {
            HomeView(showingSettings: $showingSettings, selection: $selection)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            ActivityView()
                .tabItem { Label("Activity", systemImage: "figure.run") }
                .tag(AppTab.activity)

            MealsView()
                .tabItem { Label("Meals", systemImage: "fork.knife") }
                .tag(AppTab.meals)

            VaultView(showingSettings: $showingSettings)
                .tabItem { Label("Vault", systemImage: "sterlingsign.circle.fill") }
                .tag(AppTab.vault)
        }
        .toolbarBackground(Palette.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sensoryFeedback(.selection, trigger: selection)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

/// Settings button shared by the tab roots.
struct SettingsToolbarButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "gearshape")
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityLabel("Settings")
    }
}
