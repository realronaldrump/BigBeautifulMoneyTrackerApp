import SwiftData
import SwiftUI
import WidgetKit
import Combine
import UIKit

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
    @Environment(\.scenePhase) private var scenePhase
    @Query private var preferences: [AppPreferences]
    @Query(sort: \JobProfile.sortOrder) private var jobs: [JobProfile]
    @Query private var templates: [ScheduleTemplate]
    @Query private var openShifts: [OpenShiftState]
    @Query private var scheduledShifts: [ScheduledShift]
    @State private var automationError: String?

    var body: some View {
        Group {
            if let preferences = preferences.first, preferences.onboardingCompleted, !jobs.filter({ !$0.isArchived }).isEmpty {
                MainTabContainerView(mode: preferences.selectedDisplayMode)
            } else {
                NavigationStack { OnboardingView() }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task(id: automationKey) {
            guard scenePhase == .active else { return }
            await runAutomationWhileActive()
        }
        .task(id: reminderSyncKey) {
            guard scenePhase == .active else { return }
            await ReminderManager.shared.syncShiftReminders(
                templates: templates, isEnabled: preferences.first?.remindersEnabled ?? false
            )
            guard !Task.isCancelled else { return }
            await ReminderManager.shared.syncActiveShiftNotifications(for: openShifts)
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            WidgetCenter.shared.reloadAllTimelines()
            syncLiveActivityForCurrentState()
        }
        .onReceive(NotificationCenter.default.publisher(for: PersistenceService.saveFailed)) { notification in
            automationError = notification.object as? String
        }
        .alert("Unable to Update Saved Data", isPresented: Binding(
            get: { automationError != nil }, set: { if !$0 { automationError = nil } }
        )) {
            Button("OK", role: .cancel) { automationError = nil }
        } message: {
            Text(automationError ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                syncLiveActivityForCurrentState()
            } else {
                do { try PersistenceService.save(modelContext) }
                catch { automationError = error.localizedDescription }
            }
        }
    }

    private var automationKey: String {
        let scheduled = scheduledShifts.map {
            "\($0.id)-\($0.startDate.timeIntervalSince1970)-\($0.endDate.timeIntervalSince1970)"
        }.sorted().joined(separator: ";")
        let active = openShifts.map {
            "\($0.id)-\($0.scheduledEndDate?.timeIntervalSince1970 ?? 0)"
        }.sorted().joined(separator: ";")
        return "\(scenePhase)-\(scheduled)-\(active)"
    }

    private var reminderSyncKey: String {
        let templateKey = templates.map {
            "\($0.id)-\($0.name)-\($0.weekdayRawValue)-\($0.startHour)-\($0.startMinute)-\($0.reminderMinutesBefore)-\($0.isEnabled)-\($0.job?.id.uuidString ?? "")-\($0.job?.displayName ?? "")-\($0.job?.isArchived == true)"
        }.sorted().joined(separator: ";")
        let openKey = openShifts.map {
            "\($0.id)-\($0.scheduledEndDate?.timeIntervalSince1970 ?? 0)-\($0.scheduledReminderOffsets)-\($0.job?.displayName ?? "")"
        }.sorted().joined(separator: ";")
        return "\(scenePhase)-\(preferences.first?.remindersEnabled ?? false)-\(templateKey)-\(openKey)"
    }

    private func runAutomationWhileActive() async {
        while !Task.isCancelled {
            do {
                let now = Date.now
                let ended = try ShiftController.autoEndShiftsIfNeeded(in: modelContext, at: now)
                let result = try ShiftController.reconcileScheduledShifts(in: modelContext, at: now)
                if !ended.isEmpty || !result.startedShifts.isEmpty || !result.autoCompletedShifts.isEmpty {
                    syncLiveActivityForCurrentState()
                    WidgetCenter.shared.reloadAllTimelines()
                }
                let upcoming = try modelContext.fetch(FetchDescriptor<ScheduledShift>()).map(\.startDate)
                    + modelContext.fetch(FetchDescriptor<OpenShiftState>()).compactMap(\.scheduledEndDate)
                guard let next = upcoming.filter({ $0 > now }).min() else { return }
                // Query changes restart this task when a schedule is edited.
                let delay = min(60, max(0.1, next.timeIntervalSinceNow))
                try await Task.sleep(for: .seconds(delay))
            } catch is CancellationError {
                return
            } catch {
                automationError = error.localizedDescription
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }

    private func syncLiveActivityForCurrentState() {
        guard scenePhase == .active,
              let preferences = preferences.first, preferences.onboardingCompleted else { return }

        guard let snapshot = try? ShiftController.dashboardSnapshot(in: modelContext, at: .now) else { return }
        let compensationMode = snapshot.hasSelectableEffectiveCompensation
            ? preferences.selectedCompensationDisplayMode
            : .actual
        guard preferences.liveActivitiesEnabled else {
            let finalAmount = snapshot.displayAmount(
                for: preferences.selectedDisplayMode,
                compensationMode: compensationMode
            )
            LiveActivityManager.end(
                finalAmount: finalAmount,
                mode: preferences.selectedDisplayMode,
                compensationMode: compensationMode
            )
            return
        }

        LiveActivityManager.sync(
            for: snapshot,
            mode: preferences.selectedDisplayMode,
            compensationMode: compensationMode
        )
    }
}

private struct MainTabContainerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let mode: EarningsDisplayMode

    @State private var selectedTab: AppTab = .home
    @State private var keyboardIsVisible = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0.12)) {
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
            if !keyboardIsVisible {
                FloatingTabBar(selection: $selectedTab, mode: mode)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardIsVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardIsVisible = false }
    }
}

private struct FloatingTabBar: View {
    @Environment(AppTheme.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: AppTab
    let mode: EarningsDisplayMode
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { selection = tab }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 19, weight: .semibold))
                        Text(tab.title)
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? tab.tint(theme: theme, mode: mode) : theme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(tab.tint(theme: theme, mode: mode).opacity(0.14))
                                .matchedGeometryEffect(id: "selectedTab", in: selectionNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(6)
        .glassCard(cornerRadius: 24, hasShadow: false)
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(theme.brandStroke, lineWidth: 0.7) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
    }
}
