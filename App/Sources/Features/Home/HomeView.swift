import SwiftData
import SwiftUI

private enum HomeSheet: String, Identifiable {
    case history
    case settings

    var id: String { rawValue }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme

    @Query private var preferences: [AppPreferences]
    @Query private var openShifts: [OpenShiftState]
    @Query(sort: \ShiftRecord.startDate, order: .reverse) private var shifts: [ShiftRecord]

    @State private var presentedSheet: HomeSheet?
    @State private var milestoneText: String?
    @State private var errorText: String?

    private var activeShift: OpenShiftState? { openShifts.first }

    var body: some View {
        if let preferences = preferences.first {
            TimelineView(.periodic(from: .now, by: activeShift == nil ? 60 : 1)) { context in
                let snapshot = (try? ShiftController.dashboardSnapshot(in: modelContext, at: context.date)) ?? .empty
                let displayedAmount = preferences.selectedDisplayMode == .gross ? snapshot.currentGross : snapshot.currentTakeHome
                let activitySyncKey = [
                    activeShift?.id.uuidString ?? "none",
                    String(Calendar.current.component(.minute, from: context.date)),
                    preferences.selectedDisplayMode.rawValue,
                ].joined(separator: "-")

                ZStack(alignment: .top) {
                    MoneyBackground(mode: preferences.selectedDisplayMode)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            topBar
                            modeToggle(preferences: preferences)

                            if let openShift = activeShift {
                                activeShiftContent(
                                    preferences: preferences,
                                    openShift: openShift,
                                    snapshot: snapshot,
                                    displayedAmount: displayedAmount
                                )
                            } else {
                                restingContent(preferences: preferences)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                    }

                    if let milestoneText {
                        MilestoneBanner(text: milestoneText, mode: preferences.selectedDisplayMode)
                            .padding(.top, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottom) {
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(theme.secondaryPanel)
                            .clipShape(Capsule())
                            .padding(.bottom, 16)
                    }
                }
                .task(id: Int(snapshot.currentGross.rounded(.down))) {
                    await handleMilestones(snapshot: snapshot, preferences: preferences)
                }
                .task(id: activitySyncKey) {
                    syncLiveActivityIfNeeded(snapshot: snapshot, preferences: preferences)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .history:
                    NavigationStack { HistoryView() }
                case .settings:
                    NavigationStack { SettingsView() }
                }
            }
        } else {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
        }
    }

    private var topBar: some View {
        HStack {
            topBarButton(title: "History", systemImage: "clock.arrow.circlepath") {
                presentedSheet = .history
            }
            Spacer()
            topBarButton(title: "Settings", systemImage: "slider.horizontal.3") {
                presentedSheet = .settings
            }
        }
    }

    private func topBarButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(theme.panel.opacity(0.96))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private func modeToggle(preferences: AppPreferences) -> some View {
        HStack(spacing: 10) {
            ForEach(EarningsDisplayMode.allCases) { mode in
                Button {
                    preferences.selectedDisplayMode = mode
                    try? modelContext.save()
                    HapticManager.shared.fire(.selection, enabled: preferences.hapticsEnabled)
                } label: {
                    Text(mode == .gross ? "Gross" : "Estimated Take Home")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(mode == preferences.selectedDisplayMode ? Color.black : Color.white.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(
                            Capsule()
                                .fill(mode == preferences.selectedDisplayMode ? theme.accent(for: mode) : theme.panel.opacity(0.9))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func restingContent(preferences: AppPreferences) -> some View {
        VStack(spacing: 26) {
            Spacer(minLength: 40)

            VStack(spacing: 12) {
                Text("Big Beautiful Money Tracker App")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)

                Text("Off shift.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
            }

            Button {
                do {
                    try ShiftController.startShift(in: modelContext)
                    HapticManager.shared.fire(.action, enabled: preferences.hapticsEnabled)
                } catch {
                    show(error.localizedDescription)
                }
            } label: {
                Text("Start Shift")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(theme.accent(for: preferences.selectedDisplayMode))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: theme.accent(for: preferences.selectedDisplayMode).opacity(0.32), radius: 26)
            }
            .buttonStyle(.plain)

            Text("One tap to start. One tap to stop. Everything else stays out of the way.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)

            Spacer(minLength: 120)
        }
    }

    private func activeShiftContent(
        preferences: AppPreferences,
        openShift: OpenShiftState,
        snapshot: DashboardSnapshot,
        displayedAmount: Double
    ) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 18) {
                Text(preferences.selectedDisplayMode.title.uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(theme.secondaryText)

                RollingCurrencyText(amount: displayedAmount, mode: preferences.selectedDisplayMode)

                VStack(spacing: 8) {
                    if let breakdown = snapshot.currentBreakdown {
                        Text("\(breakdown.effectiveRate.formatted(.currency(code: "USD")))/hr effective")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }

                    Text("Started \(openShift.startDate.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .padding(.top, 40)

            SummaryDrawer(snapshot: snapshot, mode: preferences.selectedDisplayMode)

            Button(role: .destructive) {
                do {
                    let endedShift = try ShiftController.endShift(in: modelContext)
                    HapticManager.shared.fire(.success, enabled: preferences.hapticsEnabled)
                    LiveActivityManager.end(finalAmount: endedShift.grossEarnings, mode: preferences.selectedDisplayMode)
                    milestoneText = endedShift.grossEarnings > (shifts.map(\.grossEarnings).max() ?? 0) ? "New all-time record" : nil
                } catch {
                    show(error.localizedDescription)
                }
            } label: {
                Text("End Shift")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func handleMilestones(snapshot: DashboardSnapshot, preferences: AppPreferences) async {
        guard let activeShift, !activeShift.celebratedFirstHundred, snapshot.currentGross >= 100 else {
            return
        }

        activeShift.celebratedFirstHundred = true
        try? modelContext.save()
        HapticManager.shared.fire(.success, enabled: preferences.hapticsEnabled)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            milestoneText = "First $100 this shift"
        }

        try? await Task.sleep(for: .seconds(2.2))
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.35)) {
                milestoneText = nil
            }
        }
    }

    private func syncLiveActivityIfNeeded(snapshot: DashboardSnapshot, preferences: AppPreferences) {
        guard preferences.liveActivitiesEnabled, let activeShift else {
            if activeShift == nil {
                LiveActivityManager.end(finalAmount: snapshot.currentGross, mode: preferences.selectedDisplayMode)
            }
            return
        }

        LiveActivityManager.startOrUpdate(
            startDate: activeShift.startDate,
            amount: preferences.selectedDisplayMode == .gross ? snapshot.currentGross : snapshot.currentTakeHome,
            rate: snapshot.currentBreakdown?.effectiveRate ?? 0,
            mode: preferences.selectedDisplayMode
        )
    }

    private func show(_ text: String) {
        withAnimation(.easeOut(duration: 0.25)) {
            errorText = text
        }
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    errorText = nil
                }
            }
        }
    }
}

private extension DashboardSnapshot {
    static let empty = DashboardSnapshot(
        currentBreakdown: nil,
        currentGross: 0,
        currentTakeHome: 0,
        payPeriodGross: 0,
        payPeriodTakeHome: 0,
        payPeriodHours: 0,
        payPeriodNightPremium: 0,
        allTimeGross: 0,
        allTimeTakeHome: 0,
        projectedPaycheckGross: 0,
        projectedPaycheckTakeHome: 0,
        projectedConfidenceLabel: "Earned so far",
        weeklyGross: 0,
        allTimeHours: 0
    )
}
