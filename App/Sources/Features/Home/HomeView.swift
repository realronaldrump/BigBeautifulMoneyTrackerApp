import SwiftData
import SwiftUI

private struct HomeSheetDestination: Identifiable {
    enum Kind {
        case activeShiftTools(UUID)
    }

    let kind: Kind
    let id = UUID()
}

struct HomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onOpenHistory: () -> Void = {}

    @Query private var preferences: [AppPreferences]
    @Query(sort: \JobProfile.sortOrder) private var jobs: [JobProfile]
    @Query(sort: \OpenShiftState.startDate) private var openShifts: [OpenShiftState]
    @Query(sort: \ScheduledShift.startDate) private var scheduledShifts: [ScheduledShift]
    @Query(sort: \ShiftRecord.startDate, order: .reverse) private var shifts: [ShiftRecord]

    @State private var presentedSheet: HomeSheetDestination?
    @State private var milestoneText: String?
    @State private var errorText: String?

    var body: some View {
        Group {
            if let preferences = preferences.first {
                HomeDashboardView(
                    preferences: preferences,
                    jobs: jobs.filter { !$0.isArchived },
                    openShifts: openShifts,
                    scheduledShifts: scheduledShifts,
                    shifts: shifts,
                    presentedSheet: $presentedSheet,
                    milestoneText: $milestoneText,
                    errorText: $errorText,
                    onOpenHistory: onOpenHistory
                )
                .sheet(item: $presentedSheet) { destination in
                    switch destination.kind {
                    case .activeShiftTools(let openShiftIdentifier):
                        if let openShift = openShifts.first(where: { $0.id == openShiftIdentifier }) {
                            NavigationStack {
                                ActiveShiftToolsView(openShift: openShift)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
                    .tint(TimecardColor.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(TimecardColor.stock.ignoresSafeArea())
            }
        }
        .task(id: milestoneText) {
            guard milestoneText != nil else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { milestoneText = nil }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HomeDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    let preferences: AppPreferences
    let jobs: [JobProfile]
    let openShifts: [OpenShiftState]
    let scheduledShifts: [ScheduledShift]
    let shifts: [ShiftRecord]

    @Binding var presentedSheet: HomeSheetDestination?
    @Binding var milestoneText: String?
    @Binding var errorText: String?
    let onOpenHistory: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: openShifts.isEmpty && !jobs.contains(where: { $0.compensationKind == .salary }) ? 60 : 1)) { context in
            if let snapshot = try? ShiftController.dashboardSnapshot(in: modelContext, at: context.date) {
            HomeDashboardSceneView(
                preferences: preferences,
                jobs: jobs,
                openShifts: openShifts,
                scheduledShifts: scheduledShifts,
                shifts: shifts,
                presentedSheet: $presentedSheet,
                milestoneText: $milestoneText,
                errorText: $errorText,
                onOpenHistory: onOpenHistory,
                contextDate: context.date,
                snapshot: snapshot
            )
            } else {
                ContentUnavailableView("Unable to Load Earnings", systemImage: "externaldrive.badge.exclamationmark", description: Text("Your saved data could not be read. Reopen the app to try again."))
            }
        }
    }
}

private struct HomeDashboardSceneView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let preferences: AppPreferences
    let jobs: [JobProfile]
    let openShifts: [OpenShiftState]
    let scheduledShifts: [ScheduledShift]
    let shifts: [ShiftRecord]

    @Binding var presentedSheet: HomeSheetDestination?
    @Binding var milestoneText: String?
    @Binding var errorText: String?
    let onOpenHistory: () -> Void

    let contextDate: Date

    let snapshot: DashboardSnapshot

    private var selectedCompensationMode: CompensationDisplayMode {
        snapshot.hasSelectableEffectiveCompensation
            ? preferences.selectedCompensationDisplayMode
            : .actual
    }

    private var displayedAmount: Double {
        snapshot.displayAmount(
            for: preferences.selectedDisplayMode,
            compensationMode: selectedCompensationMode
        )
    }

    private var displayedRate: Double? {
        snapshot.currentDisplayRate(
            for: preferences.selectedDisplayMode,
            compensationMode: selectedCompensationMode
        )
    }

    private var activeTickerLabel: String {
        preferences.selectedDisplayMode == .gross ? "Gross earned this shift" : "Estimated take-home this shift"
    }

    private var hourlyJobs: [JobProfile] { jobs.filter { $0.compensationKind == .hourly } }

    private var inactiveJobs: [JobProfile] {
        hourlyJobs.filter { job in
            snapshot.activeJobs.contains(where: { $0.id == job.id }) == false
        }
    }

    private var activitySyncKey: String {
        let activeIdentifier = snapshot.activeJobs.map(\.id).map(\.uuidString).joined(separator: ",")
        let minute = Calendar.current.component(.minute, from: contextDate)
        return "\(activeIdentifier)-\(minute)-\(preferences.selectedDisplayMode.rawValue)-\(selectedCompensationMode.rawValue)-\(preferences.liveActivitiesEnabled)"
    }

    private var selectedJob: JobProfile? {
        hourlyJobs.first { $0.id == preferences.selectedHomeJobIdentifier } ?? hourlyJobs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            TimecardHeading(title: !snapshot.activeJobs.isEmpty ? "On shift" : (hourlyJobs.isEmpty ? "Your salary" : "Off shift"),
                                          detail: contextDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            if !snapshot.activeJobs.isEmpty { PulseAura(accent: theme.accent(for: preferences.selectedDisplayMode)) }
                        }
                        ForEach(snapshot.salaryJobs) { salary in
                            SalaryDashboardCard(snapshot: salary, mode: preferences.selectedDisplayMode)
                        }
                        if snapshot.activeJobs.isEmpty && hourlyJobs.isEmpty {
                            SummaryDrawer(snapshot: snapshot, mode: preferences.selectedDisplayMode, compensationMode: selectedCompensationMode)
                        } else if snapshot.activeJobs.isEmpty {
                            restingContent
                        } else {
                            activeShiftContent
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }

                if let milestoneText {
                    MilestoneBanner(text: milestoneText)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            if let errorText {
                HStack(spacing: 12) {
                    Text(errorText)
                        .font(TypeStyle.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        self.errorText = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Dismiss error")
                }
                .foregroundStyle(TimecardColor.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(TimecardColor.inset, in: RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            if !hourlyJobs.isEmpty || !snapshot.activeJobs.isEmpty {
                primaryAction
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
        }
        .background(MoneyBackground())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TimecardMenu(title: "Earnings", items: earningsChoices) {
                    TimecardToolbarLabel(symbol: "chevron.down", title: preferences.selectedDisplayMode == .gross ? "Gross pay" : "Est. take-home")
                }
                .accessibilityHint("Choose how to display earnings")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .task(id: snapshot.currentGross.rounded(.down)) {
            await handleMilestones()
        }
        .task(id: activitySyncKey) {
            syncLiveActivityIfNeeded()
        }
    }


    private var earningsChoices: [TimecardAction] {
        var choices = [EarningsDisplayMode.gross, .takeHome].map { mode in
            TimecardAction(mode == .gross ? "Gross pay" : "Estimated take-home", selected: preferences.selectedDisplayMode == mode) {
                preferences.selectedDisplayMode = mode
                saveChanges()
            }
        }
        if snapshot.hasSelectableEffectiveCompensation {
            choices.append(TimecardAction("Include extra pay", section: "Extra pay", selected: selectedCompensationMode == .effective) {
                preferences.selectedCompensationDisplayMode = selectedCompensationMode == .effective ? .actual : .effective
                saveChanges()
            })
        }
        return choices
    }

    private var restingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            let mode = preferences.selectedDisplayMode
            let unified = snapshot.payPeriodAggregation == .unified
            let amount = unified ? snapshot.payPeriodAmount(for: mode, compensationMode: selectedCompensationMode)
                                 : snapshot.allTimeAmount(for: mode, compensationMode: selectedCompensationMode)
            if prioritizeJobPicker { nextShiftJobRow }
            PayReadout(title: (mode == .gross ? "Gross pay" : "Est. take-home") + (unified ? " this period" : " all time"),
                       amount: amount, mode: mode) {
                if unified {
                    Label("\(snapshot.payPeriodHours.formatted(.number.precision(.fractionLength(0...1)))) shift hours" + (jobs.count > 1 ? " across jobs" : ""), systemImage: "clock")
                } else {
                    Text("Jobs follow different pay cycles")
                }
            }

            if !shifts.isEmpty { WorkweekStrip(shifts: shifts, asOf: contextDate) }
            if !prioritizeJobPicker { nextShiftJobRow }
            if let next = scheduledShifts.first { upcomingScheduledShiftCard(nextScheduledShift: next) }
            SummaryDrawer(snapshot: snapshot, mode: mode, compensationMode: selectedCompensationMode)
        }
    }

    private var prioritizeJobPicker: Bool { typeSize.isAccessibilitySize && hourlyJobs.count > 1 }

    @ViewBuilder private var nextShiftJobRow: some View {
        if let selectedJob {
            Group {
                if hourlyJobs.count > 1 {
                    TimecardMenu(title: "Clock in at", items: hourlyJobs.map { job in
                        TimecardAction(job.displayName, id: job.id, swatch: job.accent.color, selected: selectedJob.id == job.id) {
                            preferences.selectedHomeJobIdentifier = job.id
                            saveChanges()
                        }
                    }) { jobSelection(selectedJob, canChoose: true) }
                    .accessibilityHint("Choose the job for this shift")
                } else {
                    jobSelection(selectedJob, canChoose: false)
                }
            }
            .padding(.vertical, 6).ruledSection()
        }
    }

    private func jobSelection(_ job: JobProfile, canChoose: Bool) -> some View {
        HStack(spacing: 12) {
            JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Clock in at").font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                Text(job.displayName).font(TypeStyle.title3).foregroundStyle(TimecardColor.ink)
            }
            Spacer()
            if canChoose { Image(systemName: "chevron.up.chevron.down").foregroundStyle(theme.grossAccent) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var activeShiftContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            PayReadout(title: activeTickerLabel, amount: displayedAmount, mode: preferences.selectedDisplayMode) {
                VStack(alignment: .leading, spacing: 5) {
                    if let start = snapshot.activeJobs.map(\.startDate).min() {
                        HStack {
                            Image(systemName: "timer")
                            Text(start, style: .timer).monospacedDigit()
                            Spacer()
                            if let rate = displayedRate {
                                Text(rate.formatted(.currency(code: "USD")) + "/hr").monospacedDigit()
                            }
                        }
                    }
                    if selectedCompensationMode == .effective { Text("Includes prorated extra pay") }
                }
            }
            activeJobsCard
            if !inactiveJobs.isEmpty { addJobMenu }
            SummaryDrawer(snapshot: snapshot, mode: preferences.selectedDisplayMode, compensationMode: selectedCompensationMode)
        }
    }

    private var primaryAction: some View {
        let isActive = !snapshot.activeJobs.isEmpty
        return Button {
            if isActive { endActiveJobs() } else if let selectedJob { startJob(selectedJob) }
        } label: {
            Label(isActive ? (snapshot.activeJobs.count == 1 ? "End shift" : "End all \(snapshot.activeJobs.count) jobs") : "Start Shift",
                  systemImage: isActive ? "stop.fill" : "play.fill")
        }
        .buttonStyle(AppActionButtonStyle(fill: isActive ? TimecardColor.vermilion : TimecardColor.cobalt))
        .disabled(!isActive && selectedJob == nil)
        .accessibilityIdentifier("home.shiftAction")
        .accessibilityHint(isActive ? "Save tracked work to History" : "Begin tracking earnings for the selected job")
    }

    private var activeJobsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Active jobs")
                    .font(TypeStyle.title3)
                    .foregroundStyle(TimecardColor.ink)
                Spacer()
            }

            ForEach(snapshot.activeJobs) { job in
                Button {
                    if let open = openShifts.first(where: { $0.job?.id == job.id }) {
                        presentedSheet = HomeSheetDestination(kind: .activeShiftTools(open.id))
                    }
                } label: {
                    HStack(spacing: 12) {
                        JobInitialBadge(name: job.name, accent: job.accent.color, size: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.name).font(TypeStyle.title3).foregroundStyle(TimecardColor.ink)
                            Text("Started \(job.startDate.formatted(date: .omitted, time: .shortened))")
                                .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                            if let end = job.scheduledEndDate {
                                Text("Ends \(end.formatted(date: .abbreviated, time: .shortened))").font(TypeStyle.caption)
                            }
                            if snapshot.activeJobs.count > 1 {
                                Text(job.displayAmount(for: preferences.selectedDisplayMode, compensationMode: selectedCompensationMode),
                                     format: .currency(code: "USD")).monospacedDigit()
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.secondaryText)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit this shift")
            }
        }
        .padding(18)
        .ruledSection()
    }

    private var addJobMenu: some View {
        TimecardMenu(title: "Start another job", items: inactiveJobs.map { job in
            TimecardAction(job.displayName, id: job.id, symbol: "play.fill") { startJob(job) }
        }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Start Another Job")
                Spacer()
                Text("\(inactiveJobs.count) available")
                    .font(TypeStyle.caption)
            }
            .font(.system(.body, design: .default, weight: .semibold))
            .foregroundStyle(TimecardColor.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, CornerRadius.cardSmall)
        }
        .buttonStyle(.plain)
        .ruledSection()
    }

    private func upcomingScheduledShiftCard(nextScheduledShift: ScheduledShift) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Next scheduled shift", systemImage: "calendar")
                    .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                Spacer(minLength: 4)
                Button("Manage", action: onOpenHistory)
                    .font(TypeStyle.callout).foregroundStyle(theme.grossAccent)
                    .frame(minHeight: 44)
            }
            Text(nextScheduledShift.startDate.formatted(date: .complete, time: .shortened))
                .font(TypeStyle.title3).foregroundStyle(TimecardColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let job = nextScheduledShift.job { jobBadge(for: job) }
            Text("Planned until \(nextScheduledShift.endDate.formatted(date: .abbreviated, time: .shortened)).")
                .font(TypeStyle.callout).foregroundStyle(theme.secondaryText)
            Text("Applied while the app is open, or the next time you return.")
                .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
            if scheduledShifts.count > 1 {
                Text("\(scheduledShifts.count) shifts scheduled").font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
            }
            if !nextScheduledShift.note.isEmpty {
                Text(nextScheduledShift.note).font(TypeStyle.callout).foregroundStyle(theme.secondaryText).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).ruledSection()
    }

    private func jobBadge(for job: JobProfile) -> some View {
        HStack(spacing: Spacing.sm) {
            JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 22)
            Text(job.displayName)
                .font(.system(.caption, design: .default, weight: .bold))
                .foregroundStyle(job.accent.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, Spacing.sm)
        .background(job.accent.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func startJob(_ job: JobProfile) {
        do {
            try ShiftController.startShifts(in: modelContext, jobIdentifiers: [job.id])
            preferences.selectedHomeJobIdentifier = job.id
            try PersistenceService.save(modelContext)
            HapticManager.shared.fire(.action, enabled: preferences.hapticsEnabled)
        } catch {
            show(error.localizedDescription)
        }
    }

    private func endActiveJobs() {
        do {
            let finalAmount = snapshot.displayAmount(
                for: preferences.selectedDisplayMode,
                compensationMode: selectedCompensationMode
            )
            let endedShifts = try ShiftController.endAllShifts(in: modelContext)

            HapticManager.shared.fire(.success, enabled: preferences.hapticsEnabled)
            LiveActivityManager.end(
                finalAmount: finalAmount,
                mode: preferences.selectedDisplayMode,
                compensationMode: selectedCompensationMode
            )
            Task { await ReminderManager.shared.cancelActiveShiftNotifications() }

            if endedShifts.count == 1,
               let endedShift = endedShifts.first,
               endedShift.grossEarnings > (shifts.map(\.grossEarnings).max() ?? 0) {
                milestoneText = "New all-time record"
            } else if endedShifts.count > 1 {
                milestoneText = "\(endedShifts.count) jobs saved to history"
            }
        } catch {
            show(error.localizedDescription)
        }
    }

    private func handleMilestones() async {
        guard let eligibleJob = snapshot.activeJobs.first(where: { activeJob in
            activeJob.currentGross >= 100 &&
            openShifts.contains(where: {
                $0.job?.id == activeJob.id && !$0.celebratedFirstHundred
            })
        }) else {
            return
        }

        guard let openShift = openShifts.first(where: { $0.job?.id == eligibleJob.id }) else {
            return
        }

        openShift.celebratedFirstHundred = true
        do { try PersistenceService.save(modelContext) } catch {
            show(error.localizedDescription)
            return
        }
        HapticManager.shared.fire(.success, enabled: preferences.hapticsEnabled)
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)) {
            milestoneText = "\(eligibleJob.name) crossed $100"
        }

    }

    private func syncLiveActivityIfNeeded() {
        syncLiveActivity(for: snapshot)
    }

    private func syncLiveActivity(for dashboardSnapshot: DashboardSnapshot) {
        guard preferences.liveActivitiesEnabled else {
            let finalAmount = dashboardSnapshot.displayAmount(
                for: preferences.selectedDisplayMode,
                compensationMode: selectedCompensationMode
            )
            LiveActivityManager.end(
                finalAmount: finalAmount,
                mode: preferences.selectedDisplayMode,
                compensationMode: selectedCompensationMode
            )
            return
        }

        LiveActivityManager.sync(
            for: dashboardSnapshot,
            mode: preferences.selectedDisplayMode,
            compensationMode: selectedCompensationMode
        )
    }

    private func saveChanges() {
        do { try PersistenceService.save(modelContext) } catch { show(error.localizedDescription) }
    }

    private func show(_ text: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            errorText = text
        }

    }
}

private struct ActiveShiftToolsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppTheme.self) private var theme
    @Query private var preferences: [AppPreferences]

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
        _selectedOffsets = State(initialValue: Set(openShift.scheduledEndDate == nil ? [15] : openShift.scheduledReminderOffsets))
    }

    var body: some View {
        TimecardForm {
            Section {
                TimecardDateField("Started", selection: $startDate, maximum: Date.now)
            }

            Section("Planned End") {
                Toggle("Stop this shift automatically", isOn: $hasScheduledEnd)
                if hasScheduledEnd {
                    TimecardDateField("Shift should end", selection: $scheduledEndDate, minimum: startDate)
                    ShiftDurationSummary(startDate: startDate, endDate: scheduledEndDate)

                    DisclosureGroup("Reminders") {
                        ForEach(reminderPresets, id: \.self) { offset in
                            Toggle(isOn: binding(for: offset)) {
                                Text(reminderLabel(for: offset))
                            }
                        }
                    }
                }
            }

            Section {
                Button("Save & end this shift", systemImage: "stop.fill") {
                    do {
                        try ShiftController.updateOpenShift(
                            in: modelContext, editing: openShift, startDate: startDate,
                            scheduledEndDate: hasScheduledEnd ? scheduledEndDate : nil,
                            reminderOffsets: Array(selectedOffsets).sorted(by: >)
                        )
                        try ShiftController.endShift(in: modelContext, openShift: openShift)
                        HapticManager.shared.fire(.success, enabled: preferences.first?.hapticsEnabled ?? false)
                        dismiss()
                    } catch { errorText = error.localizedDescription }
                }
                .foregroundStyle(theme.stopAccent)
            } footer: {
                Text("Saves this job’s tracked work to History. Other active jobs keep running.")
            }
            if let errorText {
                Section { AppInlineNotice(message: errorText) }
            }
        }
        .appKeyboardToolbar()
        .scrollContentBackground(.hidden)
        .background(MoneyBackground())
        .navigationTitle(openShift.job?.displayName ?? "Shift Tools")
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
                editing: openShift,
                startDate: startDate,
                scheduledEndDate: endDate,
                reminderOffsets: Array(selectedOffsets).sorted(by: >)
            )

            Task {
                let refreshedOpenShifts = (try? modelContext.fetch(FetchDescriptor<OpenShiftState>())) ?? []
                await ReminderManager.shared.syncActiveShiftNotifications(for: refreshedOpenShifts)
            }

            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
