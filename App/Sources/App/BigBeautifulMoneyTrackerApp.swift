import SwiftData
import SwiftUI
import WidgetKit

@main
struct BigBeautifulMoneyTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appNotificationDelegate
    @State private var theme = AppTheme()

    @State private var modelContainer: ModelContainer?
    @State private var storageError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let modelContainer {
                    RootView()
                        .modelContainer(modelContainer)
                } else if let storageError {
                    ContentUnavailableView {
                        Label("Unable to Open Saved Data", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(storageError)
                    } actions: {
                        Button("Try Again", action: loadSavedData)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView("Opening saved data…")
                }
            }
            .environment(theme)
            .preferredColorScheme(.dark)
            .task { loadSavedData() }
        }
    }

    private func loadSavedData() {
        guard modelContainer == nil else { return }
        do {
            let container = try AppModelContainerFactory.makeSharedContainer()
            try DataBootstrapper.seedIfNeeded(in: container.mainContext)
            modelContainer = container
            storageError = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            storageError = error.localizedDescription
        }
    }
}
