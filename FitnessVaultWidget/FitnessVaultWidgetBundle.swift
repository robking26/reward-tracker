import SwiftUI
import WidgetKit

@main
struct FitnessVaultWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        RestTimerLiveActivity()
        CountdownLiveActivity()
    }
}
