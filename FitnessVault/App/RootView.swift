import SwiftUI

enum AppTab: Hashable {
    case activity, nutrition, vault
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = .activity
    @State private var showingSettings = false

    var body: some View {
        TabView(selection: $selection) {
            ActivityView(showingSettings: $showingSettings)
                .tabItem { Label("Activity", systemImage: "figure.run") }
                .tag(AppTab.activity)

            NutritionView(showingSettings: $showingSettings)
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
                .tag(AppTab.nutrition)

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

#if DEBUG
#Preview {
    RootView()
        .environment(PreviewFixtures.model())
        .preferredColorScheme(.dark)
}
#endif
