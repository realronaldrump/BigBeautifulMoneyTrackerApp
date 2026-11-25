import SwiftData
import SwiftUI

private struct ShiftEditorSeed {
    let jobIdentifier: UUID?
    let startDate: Date
    let endDate: Date
    let note: String

    static func duplicate(from shift: ShiftRecord) -> ShiftEditorSeed {
        ShiftEditorSeed(
            jobIdentifier: shift.job?.id,
            startDate: shift.startDate,
            endDate: shift.endDate,
            note: shift.note
        )
    }

    static func scheduledCopy(from shift: ShiftRecord, referenceDate: Date = .now, calendar: Calendar = .current) -> ShiftEditorSeed {
        let startComponents = calendar.dateComponents([.weekday, .hour, .minute], from: shift.startDate)
        let nextStart = calendar.nextDate(
            after: referenceDate,
            matching: startComponents,
            matchingPolicy: .nextTimePreservingSmallerComponents
        ) ?? referenceDate.addingTimeInterval(60 * 60)

        let normalizedStart = calendar.date(bySetting: .second, value: 0, of: nextStart) ?? nextStart
        return ShiftEditorSeed(
            jobIdentifier: shift.job?.id,
            startDate: normalizedStart,
            endDate: normalizedStart.addingTimeInterval(shift.endDate.timeIntervalSince(shift.startDate)),
            note: shift.note
        )
    }
}

private struct HistoryEditorDestination: Identifiable {
    enum Kind {
        case editShift(ShiftRecord)
        case newShift(ShiftEditorSeed?)
        case editScheduledShift(ScheduledShift)
        case newScheduledShift(ShiftEditorSeed?)
    }

    let id = UUID()
    let kind: Kind
}

private enum HistoryScope: String, CaseIterable, Identifiable {
    case all = "All"
    case completed = "Completed"
    case scheduled = "Scheduled"
    var id: String { rawValue }
}

private enum HistoryDeletion: Identifiable {
    case completed(ShiftRecord)
    case scheduled(ScheduledShift)
    var id: UUID {
        switch self { case .completed(let shift): shift.id; case .scheduled(let shift): shift.id }
    }
    var message: String {
        switch self {
        case .completed: "This permanently removes this shift from your history."
        case .scheduled: "This removes the planned shift from your schedule."
        }
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme
    @Query(sort: \ShiftRecord.startDate, order: .reverse) private var shifts: [ShiftRecord]
    @Query(sort: \ScheduledShift.startDate) private var scheduledShifts: [ScheduledShift]
    @Query(sort: \JobProfile.sortOrder) private var jobs: [JobProfile]
    @Query private var paySchedules: [PaySchedule]
    @Query private var taxProfiles: [TaxProfile]
    @Query private var payRates: [PayRateSchedule]
    @Query private var preferences: [AppPreferences]
    @Query private var templates: [ScheduleTemplate]
    @Query private var salaryPlans: [SalaryPlan]
    @State private var destination: HistoryEditorDestination?
    @State private var pendingDeletion: HistoryDeletion?
    @State private var deleteErrorText: String?
    @State private var searchText = ""
    @State private var selectedJobID: UUID?
    @State private var scope: HistoryScope = .all

    private var hasFilters: Bool { !searchText.isEmpty || selectedJobID != nil || scope != .all }
    private var filterName: String { jobs.first { $0.id == selectedJobID }?.displayName ?? "All jobs" }
    private var hasSalaryHistory: Bool { salaryPlans.contains { selectedJobID == nil || $0.job?.id == selectedJobID } }

    private func matches(job: JobProfile?, note: String, date: Date) -> Bool {
        guard selectedJobID == nil || selectedJobID == job?.id else { return false }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [job?.displayName ?? "", note, date.formatted(date: .complete, time: .omitted)]
            .contains { $0.localizedStandardContains(query) }
    }

    private var completed: [ShiftRecord] {
        scope == .scheduled ? [] : shifts.filter { matches(job: $0.job, note: $0.note, date: $0.startDate) }
    }

    private var planned: [ScheduledShift] {
        scope == .completed ? [] : scheduledShifts.filter { matches(job: $0.job, note: $0.note, date: $0.startDate) }
    }

    private var grouped: [Date: [ShiftRecord]] {
        Dictionary(grouping: completed) { Calendar.current.dateInterval(of: .month, for: $0.startDate)?.start ?? $0.startDate }
    }

    var body: some View {
        ZStack {
            MoneyBackground()
            List {
                TimecardHeading(title: "Work history")
                    .historyListRow(top: 4, bottom: 12)
                if hasSalaryHistory {
                    Section {
                        NavigationLink {
                            SalaryHistoryView(jobIdentifier: selectedJobID)
                        } label: {
                            Label("Salary, paychecks & work hours", systemImage: "banknote.fill")
                                .font(TypeStyle.callout).padding(.vertical, 8)
                        }
                        .historyListRow(bottom: 12)
                    }
                }
                if completed.isEmpty && planned.isEmpty && !hasSalaryHistory {
                    emptyState.historyListRow(top: 12, bottom: 20)
                }
                if !planned.isEmpty {
                    Section {
                        ForEach(planned) { shift in
                            scheduledShiftRow(shift)
                        }
                    } header: { Text("Scheduled · \(planned.count)").textCase(nil) }
                }
                ForEach(grouped.keys.sorted(by: >), id: \.self) { month in
                    Section {
                        ForEach(grouped[month] ?? []) { shift in
                            completedShiftRow(shift)
                        }
                    } header: {
                        HStack {
                            Text(month.formatted(.dateTime.month(.wide).year()))
                            Spacer()
                            Text("Gross pay")
                        }.font(TimecardType.label).foregroundStyle(TimecardColor.graphite)
                            .textCase(.uppercase)
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaPadding(.bottom, 16)
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search jobs, notes, or dates")
        .toolbar {
            if jobs.count > 1 || !scheduledShifts.isEmpty || scope != .all {
                ToolbarItem(placement: .topBarLeading) { historyFilters }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if jobs.contains(where: { !$0.isArchived && $0.compensationKind == .hourly }) {
                    Button("Log completed shift", systemImage: "plus") { destination = HistoryEditorDestination(kind: .newShift(nil)) }
                    Button("Schedule future shift", systemImage: "calendar.badge.plus") { destination = HistoryEditorDestination(kind: .newScheduledShift(nil)) }
                    }
                    if !salaryPlans.isEmpty { NavigationLink("Salary history", destination: SalaryHistoryView(jobIdentifier: selectedJobID)) }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add a completed or scheduled shift")
            }
        }
        .sheet(item: $destination) { destination in
            NavigationStack {
                switch destination.kind {
                case .editShift(let shift): ShiftEditorView(editingShift: shift, availableJobs: jobs.filter { (!$0.isArchived && $0.compensationKind == .hourly) || $0.id == shift.job?.id })
                case .newShift(let seed): ShiftEditorView(editingShift: nil, seed: seed, preferredJobID: selectedJobID ?? preferences.first?.selectedHomeJobIdentifier, availableJobs: jobs.filter { !$0.isArchived && $0.compensationKind == .hourly })
                case .editScheduledShift(let shift): ScheduledShiftEditorView(editingShift: shift, availableJobs: jobs.filter { !$0.isArchived && $0.compensationKind == .hourly })
                case .newScheduledShift(let seed): ScheduledShiftEditorView(editingShift: nil, seed: seed, preferredJobID: selectedJobID ?? preferences.first?.selectedHomeJobIdentifier, availableJobs: jobs.filter { !$0.isArchived && $0.compensationKind == .hourly })
                }
            }
        }
        .confirmationDialog("Delete shift?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible, presenting: pendingDeletion) { target in
            Button("Delete shift", role: .destructive) {
                do {
                    switch target {
                    case .completed(let shift): try ShiftController.deleteShift(shift, in: modelContext)
                    case .scheduled(let shift): try ShiftController.deleteScheduledShift(shift, in: modelContext)
                    }
                } catch { deleteErrorText = error.localizedDescription }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { Text($0.message) }
        .alert("Unable to Delete Entry", isPresented: Binding(get: { deleteErrorText != nil }, set: { if !$0 { deleteErrorText = nil } })) {
            Button("OK", role: .cancel) { deleteErrorText = nil }
        } message: { Text(deleteErrorText ?? "") }
    }

    private var historyFilters: some View {
        Menu {
            if !scheduledShifts.isEmpty || scope != .all {
                Picker("Show shifts", selection: $scope) {
                    ForEach(HistoryScope.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            if jobs.count > 1 {
                Picker("Job", selection: $selectedJobID) {
                    Text("All jobs").tag(Optional<UUID>.none)
                    ForEach(jobs) { job in
                        Text(job.displayName + (job.isArchived ? " · Archived" : "")).tag(Optional(job.id))
                    }
                }
            }
        } label: {
            Image(systemName: selectedJobID != nil || scope != .all ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter history")
        .accessibilityValue(filterName + ", " + scope.rawValue)
    }

    private func scheduledShiftRow(_ shift: ScheduledShift) -> some View {
        Button { destination = HistoryEditorDestination(kind: .editScheduledShift(shift)) } label: {
            ScheduledShiftCardView(shift: shift)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit this scheduled shift")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) { pendingDeletion = .scheduled(shift) }
        }
        .historyListRow(bottom: 0)
    }

    private func completedShiftRow(_ shift: ShiftRecord) -> some View {
        Button { destination = HistoryEditorDestination(kind: .editShift(shift)) } label: {
            ShiftCardView(shift: shift, takeHomeEstimate: takeHomeEstimate(for: shift))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit shift timing and notes")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) { pendingDeletion = .completed(shift) }
        }
        .contextMenu {
            Button("Edit shift", systemImage: "pencil") { destination = HistoryEditorDestination(kind: .editShift(shift)) }
            Button("Duplicate shift", systemImage: "doc.on.doc") { destination = HistoryEditorDestination(kind: .newShift(ShiftEditorSeed.duplicate(from: shift))) }
            Button("Schedule again", systemImage: "calendar.badge.plus") { destination = HistoryEditorDestination(kind: .newScheduledShift(ShiftEditorSeed.scheduledCopy(from: shift))) }
            Button("Delete shift", systemImage: "trash", role: .destructive) { pendingDeletion = .completed(shift) }
        }
        .historyListRow(bottom: 0)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(hasFilters ? "No matching shifts" : "Your history starts here", systemImage: hasFilters ? "magnifyingglass" : "clock.arrow.circlepath")
        } description: {
            Text(hasFilters ? "Try another search or change your filters." : "Shifts you end appear here automatically. You can also log past work or plan a future shift.")
        } actions: {
            if hasFilters {
                Button("Clear filters") { searchText = ""; selectedJobID = nil; scope = .all }
                    .buttonStyle(.bordered)
            } else {
                VStack(spacing: 12) {
                    Button("Log a completed shift") { destination = HistoryEditorDestination(kind: .newShift(nil)) }
                        .buttonStyle(AppActionButtonStyle())
                    Button("Schedule future work") { destination = HistoryEditorDestination(kind: .newScheduledShift(nil)) }
                        .buttonStyle(.bordered).tint(theme.grossAccent)
                }
            }
        }
    }

    private func takeHomeEstimate(for shift: ShiftRecord) -> Double {
        guard let taxProfile = taxProfiles.first else { return shift.grossEarnings }
        return TaxEstimator.estimatedTakeHome(for: shift, allShifts: shifts, payRates: payRates, paySchedules: paySchedules, templates: templates, taxProfile: taxProfile)
    }
}

private extension View {
    func historyListRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 18, bottom: bottom, trailing: 18))
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
    }
}

private struct ShiftCardView: View {
    @Environment(AppTheme.self) private var theme
    let shift: ShiftRecord
    let takeHomeEstimate: Double

    var body: some View {
        HistoryEntryRow(job: shift.job, start: shift.startDate, end: shift.endDate,
                        hours: shift.totalHours, note: shift.note) {
            Text(shift.grossEarnings, format: .currency(code: "USD"))
                .font(TimecardType.display(27, relativeTo: .title2)).monospacedDigit()
                .foregroundStyle(TimecardColor.blueInk)
            Text("\(takeHomeEstimate.formatted(.currency(code: "USD"))) est. net").font(.caption)
            if shift.overtimeHours > 0 { Text(shift.overtimeHours.formatted() + " hrs overtime").font(.caption) }
            if shift.nightHours > 0 { Text(shift.nightHours.formatted() + " hrs night").font(.caption) }
        }
    }
}

private struct ScheduledShiftCardView: View {
    let shift: ScheduledShift

    var body: some View {
        HistoryEntryRow(job: shift.job, start: shift.startDate, end: shift.endDate,
                        hours: shift.endDate.timeIntervalSince(shift.startDate) / 3600, note: shift.note) {
            Text(shift.startDate < .now ? "Review timing" : "Scheduled")
                .font(TimecardType.label).foregroundStyle(TimecardColor.redInk)
        }
    }
}

private struct HistoryEntryRow<Detail: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let job: JobProfile?
    let start: Date
    let end: Date
    let hours: Double
    let note: String
    @ViewBuilder var detail: Detail

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 0) {
                Text(start.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(TimecardType.label)
                Text(start.formatted(.dateTime.day())).font(TimecardType.display(35, relativeTo: .title))
            }
            .foregroundStyle(TimecardColor.ink)
            .frame(minWidth: 40, alignment: .leading)
            .accessibilityLabel(start.formatted(date: .complete, time: .omitted))
            VStack(alignment: .leading, spacing: 5) {
                Text(job?.displayName ?? "Shift").font(.headline)
                Text(historyTimeRange(start: start, end: end)).font(.caption.monospacedDigit())
                Text(hours.formatted(.number.precision(.fractionLength(0...2))) + " hours").font(.caption)
                if job?.isArchived == true { Text("Archived job").font(.caption) }
                if !note.isEmpty { Text(note).font(.footnote).lineLimit(3) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) { detail }
        }
        .foregroundStyle(TimecardColor.ink)
        .padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
        .ruledSection().contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private func historyTimeRange(start: Date, end: Date) -> String {
    let endLabel = Calendar.current.isDate(start, inSameDayAs: end)
        ? end.formatted(date: .omitted, time: .shortened)
        : end.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    return start.formatted(date: .omitted, time: .shortened) + " – " + endLabel
}

private struct ShiftEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let editingShift: ShiftRecord?
    let availableJobs: [JobProfile]

    @State private var selectedJobIdentifier: UUID?
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var note: String
    @State private var errorText: String?
    @State private var confirmingDeletion = false

    init(editingShift: ShiftRecord?, seed: ShiftEditorSeed? = nil, preferredJobID: UUID? = nil, availableJobs: [JobProfile]) {
        self.editingShift = editingShift
        self.availableJobs = availableJobs
        let preferredJob = editingShift?.job?.id ?? seed?.jobIdentifier ?? preferredJobID
        _selectedJobIdentifier = State(initialValue: availableJobs.first(where: { $0.id == preferredJob })?.id ?? availableJobs.first?.id)
        _startDate = State(initialValue: editingShift?.startDate ?? seed?.startDate ?? .now.addingTimeInterval(-8 * 60 * 60))
        _endDate = State(initialValue: editingShift?.endDate ?? seed?.endDate ?? .now)
        _note = State(initialValue: editingShift?.note ?? seed?.note ?? "")
    }

    var body: some View {
        TimecardForm {
            Section {
                if availableJobs.count > 1 {
                    Picker("Job", selection: $selectedJobIdentifier) {
                        ForEach(availableJobs) { job in
                            Text(job.displayName).tag(Optional(job.id))
                        }
                    }
                }
                DatePicker("Start", selection: $startDate, in: ...Date.now)
                DatePicker("End", selection: $endDate, in: startDate...)
                ShiftDurationSummary(startDate: startDate, endDate: endDate)
                if endDate > .now {
                    AppInlineNotice(message: "Use Schedule Future Shift for planned work.")
                }
            }

            Section {
                TextField("Optional note", text: $note, axis: .vertical)
            }

            if editingShift != nil {
                Section {
                    Button(role: .destructive) { confirmingDeletion = true } label: {
                        Text("Delete this shift")
                    }
                }
            }

            if let errorText {
                Section {
                    AppInlineNotice(message: errorText)
                }
            }
        }
        .appKeyboardToolbar()
        .scrollContentBackground(.hidden)
        .background(MoneyBackground())
        .navigationTitle(editingShift == nil ? "Log Shift" : "Edit Shift")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete shift?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete shift", role: .destructive) {
                guard let editingShift else { return }
                do {
                    try ShiftController.deleteShift(editingShift, in: modelContext)
                    dismiss()
                } catch { errorText = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently removes this entry.") }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        guard let job = availableJobs.first(where: { $0.id == selectedJobIdentifier }) else {
                            errorText = "Pick a job before saving."
                            return
                        }
                        try ShiftController.saveManualShift(
                            in: modelContext,
                            editing: editingShift,
                            job: job,
                            startDate: startDate,
                            endDate: endDate,
                            note: note
                        )
                        dismiss()
                    } catch {
                        errorText = error.localizedDescription
                    }
                }
                .disabled(!(endDate > startDate && selectedJobIdentifier != nil && endDate <= .now))
            }
        }
    }
}

private struct ScheduledShiftEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let editingShift: ScheduledShift?
    let availableJobs: [JobProfile]

    @State private var selectedJobIdentifier: UUID?
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var note: String
    @State private var errorText: String?
    @State private var confirmingDeletion = false

    init(editingShift: ScheduledShift?, seed: ShiftEditorSeed? = nil, preferredJobID: UUID? = nil, availableJobs: [JobProfile]) {
        self.editingShift = editingShift
        self.availableJobs = availableJobs
        let defaultStart = seed?.startDate ?? .now.addingTimeInterval(24 * 60 * 60)
        let defaultEnd = seed?.endDate ?? defaultStart.addingTimeInterval(8 * 60 * 60)
        let preferredJob = editingShift?.job?.id ?? seed?.jobIdentifier ?? preferredJobID
        _selectedJobIdentifier = State(initialValue: availableJobs.first(where: { $0.id == preferredJob })?.id ?? availableJobs.first?.id)
        _startDate = State(initialValue: editingShift?.startDate ?? defaultStart)
        _endDate = State(initialValue: editingShift?.endDate ?? defaultEnd)
        _note = State(initialValue: editingShift?.note ?? seed?.note ?? "")
    }

    var body: some View {
        TimecardForm {
            Section {
                if availableJobs.count > 1 {
                    Picker("Job", selection: $selectedJobIdentifier) {
                        ForEach(availableJobs) { job in
                            Text(job.displayName).tag(Optional(job.id))
                        }
                    }
                }
                DatePicker("Start", selection: $startDate)
                    .onChange(of: startDate) { oldStart, newStart in
                        endDate = newStart.addingTimeInterval(max(60, endDate.timeIntervalSince(oldStart)))
                    }
                DatePicker("End", selection: $endDate, in: startDate...)
                ShiftDurationSummary(startDate: startDate, endDate: endDate)

                Text("The app applies the planned start and end when it is open, or catches up the next time you open it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Optional note", text: $note, axis: .vertical)
            }

            if editingShift != nil {
                Section {
                    Button(role: .destructive) { confirmingDeletion = true } label: {
                        Text("Delete this scheduled shift")
                    }
                }
            }

            if let errorText {
                Section {
                    AppInlineNotice(message: errorText)
                }
            }
        }
        .appKeyboardToolbar()
        .scrollContentBackground(.hidden)
        .background(MoneyBackground())
        .navigationTitle(editingShift == nil ? "Schedule Shift" : "Edit Scheduled Shift")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete shift?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete shift", role: .destructive) {
                guard let editingShift else { return }
                do {
                    try ShiftController.deleteScheduledShift(editingShift, in: modelContext)
                    dismiss()
                } catch { errorText = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently removes this entry.") }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        guard let job = availableJobs.first(where: { $0.id == selectedJobIdentifier }) else {
                            errorText = "Pick a job before saving."
                            return
                        }
                        try ShiftController.saveScheduledShift(
                            in: modelContext,
                            editing: editingShift,
                            job: job,
                            startDate: startDate,
                            endDate: endDate,
                            note: note
                        )
                        dismiss()
                    } catch {
                        errorText = error.localizedDescription
                    }
                }
                .disabled(!(endDate > startDate && selectedJobIdentifier != nil))
            }
        }
    }
}
