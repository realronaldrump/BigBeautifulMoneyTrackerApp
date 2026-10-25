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
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
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
        TimelineView(.periodic(from: .now, by: openShifts.isEmpty ? 60 : 1)) { context in
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

    @State private var selectedStartJobIdentifiers: Set<UUID> = []
    @Namespace private var modeToggleNamespace
    @Namespace private var compensationModeToggleNamespace

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

    private var activeRateLabel: String {
        let basisLabel = selectedCompensationMode == .effective ? "effective" : "tracked"
        return snapshot.activeJobs.count > 1 ? "\(basisLabel) blended" : basisLabel
    }

    private var inactiveJobs: [JobProfile] {
        jobs.filter { job in
            snapshot.activeJobs.contains(where: { $0.id == job.id }) == false
        }
    }

    private var activitySyncKey: String {
        let activeIdentifier = snapshot.activeJobs.map(\.id).map(\.uuidString).joined(separator: ",")
        let minute = Calendar.current.component(.minute, from: contextDate)
        return "\(activeIdentifier)-\(minute)-\(preferences.selectedDisplayMode.rawValue)-\(selectedCompensationMode.rawValue)-\(preferences.liveActivitiesEnabled)"
    }

    private var startButtonTitle: String {
        switch selectedStartJobIdentifiers.count {
        case 0:
            "Select a Job"
        case 1:
            "Start Shift"
        default:
            "Start \(selectedStartJobIdentifiers.count) Jobs"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            MoneyBackground(mode: preferences.selectedDisplayMode)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    modeToggle

                    if snapshot.activeJobs.isEmpty {
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
                MilestoneBanner(text: milestoneText, mode: preferences.selectedDisplayMode)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            primaryAction
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(theme.trueBlack.opacity(0.96))
        }
        .overlay(alignment: .bottom) {
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
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(theme.secondaryPanel, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .task(id: jobs.map(\.id)) {
            syncSelectedJobs()
        }
        .task(id: snapshot.currentGross.rounded(.down)) {
            await handleMilestones()
        }
        .task(id: activitySyncKey) {
            syncLiveActivityIfNeeded()
        }
    }


    private var modeToggle: some View {
        let currentMode = preferences.selectedDisplayMode
        return HStack(spacing: 0) {
            ForEach(EarningsDisplayMode.allCases) { mode in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78)) {
                        preferences.selectedDisplayMode = mode
                    }
                    saveChanges()
                    HapticManager.shared.fire(.selection, enabled: preferences.hapticsEnabled)
                } label: {
                    Text(mode == .gross ? "Gross" : "Est. take-home")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(mode == currentMode ? Color.black : Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .lineLimit(2)
                        .padding(.vertical, 4)
                        .background {
                            if mode == currentMode {
                                Capsule()
                                    .fill(theme.accent(for: mode))
                                    .shadow(color: theme.accent(for: mode).opacity(0.4), radius: 12, y: 4)
                                    .matchedGeometryEffect(id: "modeTogglePill", in: modeToggleNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == currentMode ? [.isSelected] : [])
            }
        }
        .padding(4)
        .glassCard(cornerRadius: 100, accent: theme.accent(for: currentMode), hasShadow: false)
    }

    private var compensationModeToggle: some View {
        let currentMode = selectedCompensationMode
        return HStack(spacing: 0) {
            ForEach(CompensationDisplayMode.allCases) { mode in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78)) {
                        preferences.selectedCompensationDisplayMode = mode
                    }
                    saveChanges()
                    HapticManager.shared.fire(.selection, enabled: preferences.hapticsEnabled)
                } label: {
                    Text(mode == .actual ? "Shift pay" : "With supplements")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(mode == currentMode ? Color.black : Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .lineLimit(2)
                        .padding(.vertical, 4)
                        .background {
                            if mode == currentMode {
                                Capsule()
                                    .fill(theme.accent(for: preferences.selectedDisplayMode))
                                    .shadow(color: theme.accent(for: preferences.selectedDisplayMode).opacity(0.28), radius: 10, y: 3)
                                    .matchedGeometryEffect(id: "compensationModeTogglePill", in: compensationModeToggleNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == currentMode ? [.isSelected] : [])
            }
        }
        .padding(4)
        .glassCard(cornerRadius: 100, accent: theme.accent(for: preferences.selectedDisplayMode), hasShadow: false)
    }

    private var restingContent: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Text("Off shift.")
                    .font(TypeStyle.headline)
                    .foregroundStyle(Color.white)

                Text(jobs.count > 1 ? "Choose the jobs you’re working, then start your shift." : "Ready when you are. Start your shift to see earnings live.")
                    .font(TypeStyle.body)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            if jobs.count > 1 {
                jobSelectionCard(
                    title: "Ready To Start",
                    subtitle: "You can start one job or several at the same time."
                )
            }

            if jobs.count == 1, let job = jobs.first {
                HStack(spacing: 10) {
                    JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 30)
                    Text(job.displayName).font(TypeStyle.title3).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }

            SummaryDrawer(snapshot: snapshot, mode: preferences.selectedDisplayMode, compensationMode: selectedCompensationMode)

            if let nextScheduledShift = scheduledShifts.first {
                upcomingScheduledShiftCard(nextScheduledShift: nextScheduledShift)
            }


        }
    }

    private var activeShiftContent: some View {
        VStack(spacing: Spacing.xl) {
            // Hero section with pulse aura
            ZStack {
                // Breathing pulse aura
                PulseAura(accent: theme.accent(for: preferences.selectedDisplayMode))

                VStack(spacing: 18) {
                    Text(activeTickerLabel)
                        .font(TypeStyle.callout)
                        .foregroundStyle(theme.secondaryText)

                    RollingCurrencyText(amount: displayedAmount, mode: preferences.selectedDisplayMode)
                    if selectedCompensationMode == .effective {
                        Text("Includes prorated supplements")
                            .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                    }

                    // Elapsed timer
                    if let earliestStart = snapshot.activeJobs.map(\.startDate).min() {
                        Text(earliestStart, style: .timer)
                            .font(.system(.title2, design: .monospaced, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .monospacedDigit()
                    }

                    VStack(spacing: Spacing.sm) {
                        if let displayedRate {
                            Text("\(displayedRate.formatted(.currency(code: "USD")))/hr \(activeRateLabel)")
                                .font(TypeStyle.title3)
                                .foregroundStyle(Color.white)
                        }

                        Text(snapshot.activeJobs.count == 1 ? "1 job running" : "\(snapshot.activeJobs.count) jobs running")
                            .font(TypeStyle.callout)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .padding(.top, Spacing.sm)

            activeJobsCard
            SummaryDrawer(
                snapshot: snapshot,
                mode: preferences.selectedDisplayMode,
                compensationMode: selectedCompensationMode
            )

            if !inactiveJobs.isEmpty {
                addJobMenu
            }

        }
    }

    private var primaryAction: some View {
        let isActive = !snapshot.activeJobs.isEmpty
        return Button {
            if isActive { endActiveJobs() } else { startSelectedJobs() }
        } label: {
            Label(isActive ? (snapshot.activeJobs.count == 1 ? "End shift" : "End all \(snapshot.activeJobs.count) jobs") : startButtonTitle,
                  systemImage: isActive ? "stop.fill" : "play.fill")
        }
        .buttonStyle(AppActionButtonStyle(accent: isActive ? theme.roseAccent : theme.accent(for: preferences.selectedDisplayMode)))
        .disabled(!isActive && selectedStartJobIdentifiers.isEmpty)
        .accessibilityHint(isActive ? "Save tracked work to History" : "Begin tracking earnings for the selected jobs")
    }

    private var activeJobsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Active jobs")
                    .font(TypeStyle.title3)
                    .foregroundStyle(.white)
                Spacer()
                Text("Tap to manage")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }

            if snapshot.hasSelectableEffectiveCompensation {
                VStack(alignment: .leading, spacing: 8) {
                    compensationModeToggle
                    Text(
                        selectedCompensationMode == .effective
                            ? "Includes the share of stipends and reimbursements allocated to this shift."
                            : "Shift pay includes earnings from tracked hours."
                    )
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                }
            }

            AdaptiveCardGrid(minimumWidth: snapshot.activeJobs.count == 1 ? 240 : 150, spacing: 10) {
                ForEach(snapshot.activeJobs) { job in
                    Button {
                        if let open = openShifts.first(where: { $0.job?.id == job.id }) {
                            presentedSheet = HomeSheetDestination(kind: .activeShiftTools(open.id))
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                JobInitialBadge(name: job.name, accent: job.accent.color, size: 28)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.tertiaryText)
                            }
                            Text(job.name).font(TypeStyle.title3).foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(job.displayAmount(for: preferences.selectedDisplayMode, compensationMode: selectedCompensationMode), format: .currency(code: "USD"))
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .monospacedDigit().foregroundStyle(job.accent.color)
                                .lineLimit(1).minimumScaleFactor(0.4)
                            Text("Started \(job.startDate.formatted(date: .omitted, time: .shortened))")
                                .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                            if let end = job.scheduledEndDate {
                                Text("Planned end \(end.formatted(date: .abbreviated, time: .shortened))")
                                    .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(job.accent.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Adjust timing, reminders, or end this job’s shift")
                }
            }
        }
        .padding(18)
        .glassCard(cornerRadius: CornerRadius.cardLarge, hasShadow: false)
    }

    private var addJobMenu: some View {
        Menu {
            ForEach(inactiveJobs) { job in
                Button(job.displayName) {
                    startJob(job)
                }
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Start Another Job")
                Spacer()
                Text("\(inactiveJobs.count) available")
                    .font(TypeStyle.caption)
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, CornerRadius.cardSmall)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: CornerRadius.cardLarge)
    }

    private func jobSelectionCard(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(TypeStyle.title3)
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(theme.secondaryText)

            AdaptiveCardGrid(minimumWidth: 140, spacing: 10) {
                ForEach(jobs) { job in
                    let isSelected = selectedStartJobIdentifiers.contains(job.id)
                    Button {
                        toggleStartSelection(for: job)
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack(spacing: Spacing.sm) {
                                JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 24)
                                Text(job.displayName)
                                    .font(.system(.callout, design: .rounded, weight: .bold))
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Label(isSelected ? "Selected" : "Include job", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(isSelected ? job.accent.color : theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.md)
                        .background {
                            RoundedRectangle(cornerRadius: CornerRadius.cardLarge, style: .continuous)
                                .fill(isSelected ? job.accent.color.opacity(0.16) : .clear)
                        }
                    }
                    .buttonStyle(.plain)
                    .glassCard(cornerRadius: CornerRadius.cardSmall, accent: isSelected ? job.accent.color : .white, hasShadow: false)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityLabel(job.displayName)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
        }
        .padding(18)
        .glassCard(cornerRadius: CornerRadius.cardLarge)
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
                .font(TypeStyle.title3).foregroundStyle(.white)
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
        .padding(18).glassCard(hasShadow: false)
    }

    private func jobBadge(for job: JobProfile) -> some View {
        HStack(spacing: Spacing.sm) {
            JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 22)
            Text(job.displayName)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(job.accent.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, Spacing.sm)
        .background(job.accent.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func syncSelectedJobs() {
        let availableIdentifiers = Set(jobs.map(\.id))
        selectedStartJobIdentifiers = selectedStartJobIdentifiers.intersection(availableIdentifiers)

        if selectedStartJobIdentifiers.isEmpty,
           let preferred = jobs.first(where: { $0.id == preferences.selectedHomeJobIdentifier }) ?? jobs.first {
            selectedStartJobIdentifiers = [preferred.id]
        }
    }

    private func toggleStartSelection(for job: JobProfile) {
        if selectedStartJobIdentifiers.contains(job.id) {
            selectedStartJobIdentifiers.remove(job.id)
        } else {
            selectedStartJobIdentifiers.insert(job.id)
        }

        if selectedStartJobIdentifiers.count == 1 {
            preferences.selectedHomeJobIdentifier = selectedStartJobIdentifiers.first
            saveChanges()
        }
    }

    private func startSelectedJobs() {
        do {
            let selectedIdentifiers = Array(selectedStartJobIdentifiers)
            guard !selectedIdentifiers.isEmpty else {
                throw ShiftControllerError.noJobsSelected
            }

            try ShiftController.startShifts(in: modelContext, jobIdentifiers: selectedIdentifiers)
            if selectedIdentifiers.count == 1 {
                preferences.selectedHomeJobIdentifier = selectedIdentifiers.first
                try PersistenceService.save(modelContext)
            }
            HapticManager.shared.fire(.action, enabled: preferences.hapticsEnabled)
        } catch {
            show(error.localizedDescription)
        }
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
        _selectedOffsets = State(initialValue: Set(openShift.scheduledEndDate == nil ? [30, 15, 5] : openShift.scheduledReminderOffsets))
    }

    var body: some View {
        Form {
            Section {
                BrandHeader(
                    eyebrow: openShift.job?.displayName ?? "Shift Tools",
                    subtitle: "Adjust the start time, planned end, or reminders for this job.",
                    mode: .gross,
                    compact: true
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section("Fix Start Time") {
                DatePicker("Shift started", selection: $startDate, in: ...Date.now)
                Text("Use this only if you need to correct when you actually clocked in.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }

            Section("Planned End") {
                Toggle("Stop this shift automatically", isOn: $hasScheduledEnd)
                if hasScheduledEnd {
                    DatePicker("Shift should end", selection: $scheduledEndDate, in: startDate...)
                    ShiftDurationSummary(startDate: startDate, endDate: scheduledEndDate)

                    ForEach(reminderPresets, id: \.self) { offset in
                        Toggle(isOn: binding(for: offset)) {
                            Text(reminderLabel(for: offset))
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
                .foregroundStyle(theme.roseAccent)
            } footer: {
                Text("Saves this job’s tracked work to History. Other active jobs keep running.")
            }
            if let errorText {
                Section { AppInlineNotice(message: errorText) }
            }
        }
        .appKeyboardToolbar()
        .scrollContentBackground(.hidden)
        .background(MoneyBackground(mode: .gross))
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
