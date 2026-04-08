import SwiftData
import SwiftUI

@main
struct BigBeautifulMoneyTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appNotificationDelegate
    @State private var theme = AppTheme()

    private let modelContainer = AppModelContainerFactory.makeSharedContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(theme)
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
    }
}
