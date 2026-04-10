import SwiftData
import SwiftUI

private enum AppTab: String, CaseIterable, Identifiable {
    case home
    case history
    case summary
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            "Home"
        case .history:
            "History"
        case .summary:
            "Summary"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house.fill"
        case .history:
            "clock.arrow.circlepath"
        case .summary:
            "chart.bar.xaxis"
        case .settings:
            "slider.horizontal.3"
        }
    }

    @MainActor
    func tint(theme: AppTheme, mode: EarningsDisplayMode) -> Color {
        switch self {
        case .home:
            theme.accent(for: mode)
        case .history:
            Color(red: 0.46, green: 0.74, blue: 0.98)
        case .summary:
            theme.takeHomeAccent
        case .settings:
            theme.roseAccent
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [AppPreferences]
    @Query(sort: \JobProfile.sortOrder) private var jobs: [JobProfile]

    var body: some View {
        Group {
            if let preferences = preferences.first, preferences.onboardingCompleted, !jobs.filter({ !$0.isArchived }).isEmpty {
                MainTabContainerView(mode: preferences.selectedDisplayMode)
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

private struct MainTabContainerView: View {
    let mode: EarningsDisplayMode

    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView {
                    withAnimation(.snappy(duration: 0.32, extraBounce: 0.12)) {
                        selectedTab = .history
                    }
                }
            }
            .tag(AppTab.home)
            .toolbar(.hidden, for: .tabBar)
            .tabItem {
                Label(AppTab.home.title, systemImage: AppTab.home.systemImage)
            }

            NavigationStack {
                HistoryView()
            }
            .tag(AppTab.history)
            .toolbar(.hidden, for: .tabBar)
            .tabItem {
                Label(AppTab.history.title, systemImage: AppTab.history.systemImage)
            }

            NavigationStack {
                SummaryView()
            }
            .tag(AppTab.summary)
            .toolbar(.hidden, for: .tabBar)
            .tabItem {
                Label(AppTab.summary.title, systemImage: AppTab.summary.systemImage)
            }

            NavigationStack {
                SettingsView()
            }
            .tag(AppTab.settings)
            .toolbar(.hidden, for: .tabBar)
            .tabItem {
                Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $selectedTab, mode: mode)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
    }
}

private struct FloatingTabBar: View {
    @Environment(AppTheme.self) private var theme

    @Binding var selection: AppTab
    let mode: EarningsDisplayMode

    @Namespace private var selectionNamespace

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(AppTab.allCases) { tab in
                    let isSelected = selection == tab

                    Button {
                        withAnimation(.snappy(duration: 0.32, extraBounce: 0.12)) {
                            selection = tab
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 18, weight: .semibold))

                            if isSelected {
                                Text(tab.title)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                        .foregroundStyle(isSelected ? Color.white : theme.secondaryText)
                        .padding(.horizontal, isSelected ? 16 : 14)
                        .frame(height: 52)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(tab.tint(theme: theme, mode: mode).opacity(0.16))
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                    }
                                    .matchedGeometryEffect(id: "selectedTabBackground", in: selectionNamespace)
                                    .glassEffect(
                                        .regular
                                            .tint(tab.tint(theme: theme, mode: mode).opacity(0.30))
                                            .interactive(),
                                        in: .capsule
                                    )
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(Color.white.opacity(0.06)), in: .capsule)
            .overlay {
                Capsule()
                    .strokeBorder(theme.brandStroke, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.28), radius: 24, y: 12)
        }
        .animation(.snappy(duration: 0.32, extraBounce: 0.12), value: selection)
    }
}
