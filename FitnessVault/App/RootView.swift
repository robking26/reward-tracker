import SwiftUI

/// The four destinations (N1). Settings opens as a sheet from any of them.
enum AppTab: Hashable {
    case today, coach, calendar, progress
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(CoachModel.self) private var coach
    @Environment(AppRouter.self) private var router
    @State private var tab: AppTab = .today
    @State private var showingSettings = false

    var body: some View {
        TabView(selection: $tab) {
            TodayView(showingSettings: $showingSettings, openCoach: { tab = .coach })
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
            CoachView(showingSettings: $showingSettings)
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(AppTab.coach)
            CalendarTabView(showingSettings: $showingSettings)
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)
            ProgressTabView(showingSettings: $showingSettings)
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.progress)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onChange(of: router.pending) { _, _ in follow() }
        .onAppear { follow() }
    }

    /// Links from widgets and Siri. The workout route is opened by Today, which owns the workout screen.
    private func follow() {
        guard let route = router.pending else { return }
        switch route {
        case .today:
            tab = .today
            router.pending = nil
        case .coach:
            tab = .coach
            router.pending = nil
        case .ready:
            tab = .coach
            router.pending = nil
            if !coach.hasBriefedToday { coach.send("I'm ready") }
        case .workout:
            showingSettings = false
            tab = .today
        }
    }
}

/// Opens Settings from any tab.
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
        .environment(PreviewFixtures.coach())
        .environment(PreviewFixtures.training())
        .environment(PreviewFixtures.kitchen())
        .environment(PreviewFixtures.situation())
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
#endif
