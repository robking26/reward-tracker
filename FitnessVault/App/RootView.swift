import SwiftUI

/// Vaultality is a single-page dashboard; banking and vault administration live in Settings.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showingSettings = false

    var body: some View {
        ActivityView(showingSettings: $showingSettings)
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
        .preferredColorScheme(.dark)
}
#endif
