import SwiftUI

/// The earnings dashboard, your day, the Gym and the Kitchen. Banking and vault administration live in Settings.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showingSettings = false

    var body: some View {
        TabView {
            ActivityView(showingSettings: $showingSettings)
                .tabItem { Label("Vault", systemImage: "sterlingsign.circle") }
            DayView(showingSettings: $showingSettings)
                .tabItem { Label("Day", systemImage: "calendar") }
            GymView(showingSettings: $showingSettings)
                .tabItem { Label("Gym", systemImage: "dumbbell") }
            NavigationStack {
                KitchenView(showingSettings: $showingSettings)
            }
            .tabItem { Label("Kitchen", systemImage: "fork.knife") }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

/// Opens Settings from the dashboard.
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
        .environment(PreviewFixtures.training())
        .environment(PreviewFixtures.kitchen())
        .environment(PreviewFixtures.planner())
        .environment(PreviewFixtures.routines())
        .environment(PreviewFixtures.journal())
        .environment(PreviewFixtures.battery())
        .environment(PreviewFixtures.teas())
        .preferredColorScheme(.dark)
}
#endif
