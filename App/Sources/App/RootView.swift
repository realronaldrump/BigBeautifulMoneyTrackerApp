import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [AppPreferences]
    @Query private var payRates: [PayRateSchedule]

    var body: some View {
        Group {
            if let preferences = preferences.first, preferences.onboardingCompleted, !payRates.isEmpty {
                NavigationStack {
                    HomeView()
                }
            } else {
                OnboardingView()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            try? DataBootstrapper.seedIfNeeded(in: modelContext)
        }
    }
}
