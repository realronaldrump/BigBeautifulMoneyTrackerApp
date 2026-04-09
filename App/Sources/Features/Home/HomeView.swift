import SwiftData
import SwiftUI

private enum HomeSheet: String, Identifiable {
    case history
    case settings
    case activeShiftTools

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
                let autoStopKey = [
                    activeShift?.id.uuidString ?? "none",
                    String(Int(context.date.timeIntervalSince1970)),
                    String(Int(activeShift?.scheduledEndDate?.timeIntervalSince1970 ?? 0)),
                ].joined(separator: "-")

                ZStack(alignment: .top) {
                    MoneyBackground(mode: preferences.selectedDisplayMode)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            topBar
                            homeBrandHeader(preferences: preferences)
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
                .task(id: autoStopKey) {
                    await handleScheduledAutoStop(at: context.date, preferences: preferences)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .history:
                    NavigationStack { HistoryView() }
                case .settings:
                    NavigationStack { SettingsView() }
                case .activeShiftTools:
                    if let activeShift {
                        NavigationStack {
                            ActiveShiftToolsView(openShift: activeShift)
                        }
                    }
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

    private func homeBrandHeader(preferences: AppPreferences) -> some View {
        BrandHeader(
            eyebrow: activeShift == nil ? "Ready When You Are" : "Live Money Flow",
            subtitle: activeShift == nil
                ? "Davis's Big Beautiful Money Tracker App keeps every shift one tap away and every dollar beautifully legible."
                : "Davis's Big Beautiful Money Tracker App keeps this shift live, elegant, and easy to scan in real time.",
            mode: preferences.selectedDisplayMode,
            compact: activeShift != nil
        )
    }

    private func restingContent(preferences: AppPreferences) -> some View {
        VStack(spacing: 26) {
            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Text("Off shift.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)

                Text("The next tap starts a polished live ledger for today.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
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

            Text("One tap to start. One tap to stop. Davis's Big Beautiful Money Tracker App keeps the controls quiet so the money stays center stage.")
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

                    HStack(spacing: 8) {
                        Text("Started \(openShift.startDate.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.secondaryText)

                        Button {
                            presentedSheet = .activeShiftTools
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.secondaryText)
                                .padding(8)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if let scheduledEndDate = openShift.scheduledEndDate {
                        Text("Planned end \(scheduledEndDate.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .padding(.top, 8)

            SummaryDrawer(snapshot: snapshot, mode: preferences.selectedDisplayMode)

            Button(role: .destructive) {
                do {
                    let endedShift = try ShiftController.endShift(in: modelContext)
                    HapticManager.shared.fire(.success, enabled: preferences.hapticsEnabled)
                    LiveActivityManager.end(finalAmount: endedShift.grossEarnings, mode: preferences.selectedDisplayMode)
                    Task { await ReminderManager.shared.cancelActiveShiftNotifications() }
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

    private func handleScheduledAutoStop(at date: Date, preferences: AppPreferences) async {
        do {
            if let endedShift = try ShiftController.autoEndShiftIfNeeded(in: modelContext, at: date) {
                HapticManager.shared.fire(.success, enabled: preferences.hapticsEnabled)
                LiveActivityManager.end(finalAmount: endedShift.grossEarnings, mode: preferences.selectedDisplayMode)
                await ReminderManager.shared.cancelActiveShiftNotifications()
                await ReminderManager.shared.notifyShiftAutoStopped(at: endedShift.endDate)
                await MainActor.run {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        milestoneText = "Shift stopped at \(endedShift.endDate.formatted(date: .omitted, time: .shortened))"
                    }
                }
            }
        } catch {
            show(error.localizedDescription)
        }
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

private struct ActiveShiftToolsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme

    let openShift: OpenShiftState

    @State private var startDate: Date
    @State private var hasScheduledEnd: Bool
    @State private var scheduledEndDate: Date
    @State private var selectedOffsets: Set<Int>
    @State private var errorText: String?

    private let reminderPresets = [60, 30, 15, 5]

    init(openShift: OpenShiftState) {
        self.openShift = openShift
        _startDate = State(initialValue: openShift.startDate)
        let scheduledEnd = openShift.scheduledEndDate ?? Date.now.addingTimeInterval(8 * 60 * 60)
        _hasScheduledEnd = State(initialValue: openShift.scheduledEndDate != nil)
        _scheduledEndDate = State(initialValue: scheduledEnd)
        _selectedOffsets = State(initialValue: Set(openShift.scheduledReminderOffsets.isEmpty ? [30, 15, 5] : openShift.scheduledReminderOffsets))
    }

    var body: some View {
        Form {
            Section("Fix Start Time") {
                DatePicker("Shift started", selection: $startDate)
                Text("Use this only if you need to correct when you actually clocked in.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }

            Section("Planned End") {
                Toggle("Stop this shift automatically", isOn: $hasScheduledEnd)
                if hasScheduledEnd {
                    DatePicker("Shift should end", selection: $scheduledEndDate)

                    ForEach(reminderPresets, id: \.self) { offset in
                        Toggle(isOn: binding(for: offset)) {
                            Text(reminderLabel(for: offset))
                        }
                    }
                }
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Shift Tools")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
            }
        }
    }

    private func binding(for offset: Int) -> Binding<Bool> {
        Binding(
            get: { selectedOffsets.contains(offset) },
            set: { isEnabled in
                if isEnabled {
                    selectedOffsets.insert(offset)
                } else {
                    selectedOffsets.remove(offset)
                }
            }
        )
    }

    private func reminderLabel(for offset: Int) -> String {
        if offset >= 60 {
            let hours = offset / 60
            return hours == 1 ? "Remind me 1 hour before" : "Remind me \(hours) hours before"
        }
        return "Remind me \(offset) minutes before"
    }

    private func save() {
        do {
            let endDate = hasScheduledEnd ? scheduledEndDate : nil
            try ShiftController.updateOpenShift(
                in: modelContext,
                startDate: startDate,
                scheduledEndDate: endDate,
                reminderOffsets: Array(selectedOffsets).sorted(by: >)
            )

            Task {
                if let refreshedOpenShift = try? DataBootstrapper.first(OpenShiftState.self, in: modelContext), refreshedOpenShift.id == openShift.id {
                    await ReminderManager.shared.syncActiveShiftNotifications(for: refreshedOpenShift)
                } else {
                    await ReminderManager.shared.cancelActiveShiftNotifications()
                }
            }

            dismiss()
        } catch {
            errorText = error.localizedDescription
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
