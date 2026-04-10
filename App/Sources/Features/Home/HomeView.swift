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
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HomeDashboardView: View {
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
                contextDate: context.date
            )
        }
    }
}

private struct HomeDashboardSceneView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme

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

    private var snapshot: DashboardSnapshot {
        (try? ShiftController.dashboardSnapshot(in: modelContext, at: contextDate)) ?? .empty
    }

    private var displayedAmount: Double {
        preferences.selectedDisplayMode == .gross ? snapshot.currentGross : snapshot.currentTakeHome
    }

    private var inactiveJobs: [JobProfile] {
        jobs.filter { job in
            snapshot.activeJobs.contains(where: { $0.id == job.id }) == false
        }
    }

    private var activitySyncKey: String {
        let activeIdentifier = snapshot.activeJobs.map(\.id).map(\.uuidString).joined(separator: ",")
        let minute = Calendar.current.component(.minute, from: contextDate)
        return "\(activeIdentifier)-\(minute)-\(preferences.selectedDisplayMode.rawValue)"
    }

    private var automationKey: String {
        let activeIdentifier = openShifts.map(\.id).map(\.uuidString).joined(separator: ",")
        let scheduledIdentifier = scheduledShifts.map(\.id).map(\.uuidString).joined(separator: ",")
        let currentTime = Int(contextDate.timeIntervalSince1970)
        return "\(activeIdentifier)-\(scheduledIdentifier)-\(currentTime)"
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
                .padding(.bottom, 130)
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
        .task(id: jobs.map(\.id)) {
            syncSelectedJobs()
        }
        .task(id: snapshot.currentGross.rounded(.down)) {
            await handleMilestones()
        }
        .task(id: activitySyncKey) {
            syncLiveActivityIfNeeded()
        }
        .task(id: automationKey) {
            await handleShiftAutomation()
        }
    }


    private var modeToggle: some View {
        let currentMode = preferences.selectedDisplayMode
        return HStack(spacing: 0) {
            ForEach(EarningsDisplayMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        preferences.selectedDisplayMode = mode
                    }
                    try? modelContext.save()
                    HapticManager.shared.fire(.selection, enabled: preferences.hapticsEnabled)
                } label: {
                    Text(mode == .gross ? "Gross" : "Take Home")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(mode == currentMode ? Color.black : Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
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
            }
        }
        .padding(4)
        .glassCard(cornerRadius: 100, accent: theme.accent(for: currentMode), hasShadow: false)
    }

    private var restingContent: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Text("Off shift.")
                    .font(TypeStyle.headline)
                    .foregroundStyle(Color.white)

                Text("Choose one or more jobs, then start tracking.")
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

            Button {
                startSelectedJobs()
            } label: {
                Text(startButtonTitle)
                    .font(TypeStyle.title)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(theme.accent(for: preferences.selectedDisplayMode))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.cardLarge, style: .continuous))
                    .shadow(color: theme.accent(for: preferences.selectedDisplayMode).opacity(0.32), radius: 26)
            }
            .buttonStyle(.plain)
            .disabled(selectedStartJobIdentifiers.isEmpty)
            .opacity(selectedStartJobIdentifiers.isEmpty ? 0.7 : 1)

            if let nextScheduledShift = scheduledShifts.first {
                upcomingScheduledShiftCard(nextScheduledShift: nextScheduledShift)
            }

            Spacer(minLength: 120)
        }
    }

    private var activeShiftContent: some View {
        VStack(spacing: Spacing.xl) {
            // Hero section with pulse aura
            ZStack {
                // Breathing pulse aura
                PulseAura(accent: theme.accent(for: preferences.selectedDisplayMode))

                VStack(spacing: 18) {
                    Text(preferences.selectedDisplayMode.title.uppercased())
                        .font(TypeStyle.caption)
                        .tracking(1.8)
                        .foregroundStyle(theme.secondaryText)

                    RollingCurrencyText(amount: displayedAmount, mode: preferences.selectedDisplayMode)

                    // Elapsed timer
                    if let earliestStart = snapshot.activeJobs.map(\.startDate).min() {
                        Text(earliestStart, style: .timer)
                            .font(.system(size: 22, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                            .monospacedDigit()
                    }

                    VStack(spacing: Spacing.sm) {
                        if let breakdown = snapshot.currentBreakdown {
                            let rateLabel = snapshot.activeJobs.count > 1 ? "blended" : "effective"
                            Text("\(breakdown.effectiveRate.formatted(.currency(code: "USD")))/hr \(rateLabel)")
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
            SummaryDrawer(snapshot: snapshot, mode: preferences.selectedDisplayMode)

            if !inactiveJobs.isEmpty {
                addJobMenu
            }

            Button(role: .destructive) {
                endActiveJobs()
            } label: {
                Text(snapshot.activeJobs.count == 1 ? "End Shift" : "End All Jobs")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
            }
            .buttonStyle(.plain)
            .glassCard(cornerRadius: CornerRadius.cardLarge)
        }
    }

    private var activeJobsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Live Jobs")
                    .font(TypeStyle.title3)
                    .foregroundStyle(.white)
                Spacer()
                Text("Tap a job to adjust its timer")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
            }

            if snapshot.activeJobs.count == 1 {
                let activeJob = snapshot.activeJobs[0]
                Button {
                    if let openShift = openShifts.first(where: { $0.job?.id == activeJob.id }) {
                        presentedSheet = HomeSheetDestination(kind: .activeShiftTools(openShift.id))
                    }
                } label: {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: Spacing.sm) {
                                JobInitialBadge(name: activeJob.name, accent: activeJob.accent.color, size: 28)
                                Text(activeJob.name)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            
                            HStack(spacing: Spacing.sm) {
                                Text("Started \(activeJob.startDate.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(theme.secondaryText)
                                
                                if let scheduledEndDate = activeJob.scheduledEndDate {
                                    Text("•")
                                        .foregroundStyle(theme.tertiaryText)
                                    Text("Ends \(scheduledEndDate.formatted(date: .omitted, time: .shortened))")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(theme.secondaryText)
                                }
                            }
                        }
                        
                        Spacer(minLength: 12)
                        
                        Text(
                            preferences.selectedDisplayMode == .gross
                            ? activeJob.currentGross.formatted(.currency(code: "USD"))
                            : activeJob.currentTakeHome.formatted(.currency(code: "USD"))
                        )
                        .font(TypeStyle.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(activeJob.accent.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .buttonStyle(.plain)
                .glassCard(cornerRadius: CornerRadius.cardLarge, accent: activeJob.accent.color)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(snapshot.activeJobs) { activeJob in
                        Button {
                            if let openShift = openShifts.first(where: { $0.job?.id == activeJob.id }) {
                                presentedSheet = HomeSheetDestination(kind: .activeShiftTools(openShift.id))
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: Spacing.sm) {
                                    JobInitialBadge(name: activeJob.name, accent: activeJob.accent.color, size: 24)
                                    Text(activeJob.name)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }

                                Text(
                                    preferences.selectedDisplayMode == .gross
                                    ? activeJob.currentGross.formatted(.currency(code: "USD"))
                                    : activeJob.currentTakeHome.formatted(.currency(code: "USD"))
                                )
                                .font(TypeStyle.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(activeJob.accent.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                                Text("Started \(activeJob.startDate.formatted(date: .omitted, time: .shortened))")
                                    .font(TypeStyle.caption)
                                    .foregroundStyle(theme.secondaryText)

                                if let scheduledEndDate = activeJob.scheduledEndDate {
                                    Text("Ends \(scheduledEndDate.formatted(date: .omitted, time: .shortened))")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(theme.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                            .padding(CornerRadius.cardSmall)
                        }
                        .buttonStyle(.plain)
                        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: activeJob.accent.color)
                    }
                }
            }
        }
        .padding(18)
        .glassCard(cornerRadius: CornerRadius.cardLarge)
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
            .font(.system(size: 16, weight: .semibold, design: .rounded))
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
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(jobs) { job in
                    let isSelected = selectedStartJobIdentifiers.contains(job.id)
                    Button {
                        toggleStartSelection(for: job)
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack(spacing: Spacing.sm) {
                                JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 24)
                                Text(job.displayName)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }

                            Text(isSelected ? "Selected" : "Tap to include")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
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
                    .glassCard(cornerRadius: CornerRadius.cardLarge, accent: isSelected ? job.accent.color : .white)
                }
            }
        }
        .padding(18)
        .glassCard(cornerRadius: CornerRadius.cardLarge)
    }

    private func upcomingScheduledShiftCard(nextScheduledShift: ScheduledShift) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(scheduledShifts.count == 1 ? "1 shift scheduled" : "\(scheduledShifts.count) shifts scheduled")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.secondaryText)

                    Text(nextScheduledShift.startDate.formatted(date: .complete, time: .shortened))
                        .font(TypeStyle.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }

                Spacer()

                Button {
                    onOpenHistory()
                } label: {
                    Text("Manage")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(theme.grossAccent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if let job = nextScheduledShift.job {
                jobBadge(for: job)
            }

            Text("Auto-starts at \(nextScheduledShift.startDate.formatted(date: .omitted, time: .shortened)) and auto-stops at \(nextScheduledShift.endDate.formatted(date: .omitted, time: .shortened)).")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)

            if !nextScheduledShift.note.isEmpty {
                Text(nextScheduledShift.note)
                    .font(TypeStyle.caption)
                    .foregroundStyle(Color.white.opacity(0.88))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: CornerRadius.cardLarge)
    }

    private func jobBadge(for job: JobProfile) -> some View {
        HStack(spacing: Spacing.sm) {
            JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 22)
            Text(job.displayName)
                .font(.system(size: 12, weight: .bold, design: .rounded))
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
            try? modelContext.save()
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
                try? modelContext.save()
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
            try? modelContext.save()
            HapticManager.shared.fire(.action, enabled: preferences.hapticsEnabled)
        } catch {
            show(error.localizedDescription)
        }
    }

    private func endActiveJobs() {
        do {
            let endedShifts = try ShiftController.endAllShifts(in: modelContext)
            let finalAmount = preferences.selectedDisplayMode == .gross
                ? endedShifts.reduce(0) { $0 + $1.grossEarnings }
                : snapshot.currentTakeHome

            HapticManager.shared.fire(.success, enabled: preferences.hapticsEnabled)
            LiveActivityManager.end(finalAmount: finalAmount, mode: preferences.selectedDisplayMode)
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
        try? modelContext.save()
        HapticManager.shared.fire(.success, enabled: preferences.hapticsEnabled)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            milestoneText = "\(eligibleJob.name) crossed $100"
        }

        try? await Task.sleep(for: .seconds(2.2))
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.35)) {
                milestoneText = nil
            }
        }
    }

    private func syncLiveActivityIfNeeded() {
        syncLiveActivity(for: snapshot)
    }

    private func syncLiveActivity(for dashboardSnapshot: DashboardSnapshot) {
        guard preferences.liveActivitiesEnabled, !dashboardSnapshot.activeJobs.isEmpty else {
            if dashboardSnapshot.activeJobs.isEmpty {
                LiveActivityManager.end(finalAmount: dashboardSnapshot.currentGross, mode: preferences.selectedDisplayMode)
            }
            return
        }

        let title = dashboardSnapshot.activeJobs.count == 1
            ? dashboardSnapshot.activeJobs[0].name
            : "\(dashboardSnapshot.activeJobs.count) Jobs Active"

        LiveActivityManager.startOrUpdate(
            title: title,
            startDate: dashboardSnapshot.activeJobs.map(\.startDate).min() ?? .now,
            amount: preferences.selectedDisplayMode == .gross ? dashboardSnapshot.currentGross : dashboardSnapshot.currentTakeHome,
            rate: dashboardSnapshot.currentBreakdown?.effectiveRate ?? 0,
            mode: preferences.selectedDisplayMode
        )
    }

    private func handleShiftAutomation() async {
        do {
            var bannerText: String?
            var shouldFireHaptic = false

            let endedShifts = try ShiftController.autoEndShiftsIfNeeded(in: modelContext, at: contextDate)
            if !endedShifts.isEmpty {
                shouldFireHaptic = true
                for endedShift in endedShifts {
                    await ReminderManager.shared.notifyShiftAutoStopped(at: endedShift.endDate)
                }

                bannerText = endedShifts.count == 1
                    ? "Scheduled stop reached for \(endedShifts[0].job?.displayName ?? "a job")"
                    : "\(endedShifts.count) jobs auto-stopped"
            }

            let scheduleResult = try ShiftController.reconcileScheduledShifts(in: modelContext, at: contextDate)

            let activeShiftStateChanged = !endedShifts.isEmpty || !scheduleResult.startedShifts.isEmpty
            if activeShiftStateChanged {
                let refreshedOpenShifts = (try? modelContext.fetch(FetchDescriptor<OpenShiftState>())) ?? []
                await ReminderManager.shared.syncActiveShiftNotifications(for: refreshedOpenShifts)

                let refreshedSnapshot = (try? ShiftController.dashboardSnapshot(in: modelContext, at: contextDate)) ?? .empty
                await MainActor.run {
                    syncLiveActivity(for: refreshedSnapshot)
                }
            }

            if !scheduleResult.startedShifts.isEmpty {
                shouldFireHaptic = true
                if scheduleResult.startedShifts.count == 1 {
                    bannerText = "\(scheduleResult.startedShifts[0].job?.displayName ?? "Scheduled job") started"
                } else {
                    bannerText = "\(scheduleResult.startedShifts.count) scheduled jobs started"
                }
            } else if !scheduleResult.autoCompletedShifts.isEmpty {
                shouldFireHaptic = true
                bannerText = scheduleResult.autoCompletedShifts.count == 1
                    ? "Scheduled shift added to history"
                    : "\(scheduleResult.autoCompletedShifts.count) scheduled shifts added to history"
            }

            if shouldFireHaptic {
                HapticManager.shared.fire(.success, enabled: preferences.hapticsEnabled)
            }

            if let bannerText {
                await MainActor.run {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        milestoneText = bannerText
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
            Section {
                BrandHeader(
                    eyebrow: openShift.job?.displayName ?? "Shift Tools",
                    subtitle: "Adjust timing, auto-stop, and reminders for this live job without leaving the ticker.",
                    mode: .gross,
                    compact: true
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            }

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

private extension DashboardSnapshot {
    static let empty = DashboardSnapshot(
        currentBreakdown: nil,
        activeJobs: [],
        currentGross: 0,
        currentTakeHome: 0,
        payPeriodAggregation: .unified,
        payPeriodGross: 0,
        payPeriodTakeHome: 0,
        payPeriodHours: 0,
        payPeriodNightPremium: 0,
        allTimeGross: 0,
        allTimeTakeHome: 0,
        projectedPaycheckGross: 0,
        projectedPaycheckTakeHome: 0,
        projectedConfidenceLabel: "Earned so far",
        allTimeHours: 0
    )
}
