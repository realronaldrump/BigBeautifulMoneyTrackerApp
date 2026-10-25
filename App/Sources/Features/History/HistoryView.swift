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
    @Query private var templates: [ScheduleTemplate]
    @State private var destination: HistoryEditorDestination?
    @State private var pendingDeletion: HistoryDeletion?
    @State private var deleteErrorText: String?
    @State private var searchText = ""
    @State private var selectedJobID: UUID?
    @State private var scope: HistoryScope = .all

    private var hasFilters: Bool { !searchText.isEmpty || selectedJobID != nil || scope != .all }
    private var filterName: String { jobs.first { $0.id == selectedJobID }?.displayName ?? "All jobs" }

    private func matches(job: JobProfile?, note: String, date: Date) -> Bool {
        guard selectedJobID == nil || selectedJobID == job?.id else { return false }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [job?.displayName ?? "", note, date.formatted(date: .complete, time: .omitted)]
            .contains { $0.localizedStandardContains(query) }
    }

    var body: some View {
        let completed = scope == .scheduled ? [] : shifts.filter { matches(job: $0.job, note: $0.note, date: $0.startDate) }
        let planned = scope == .completed ? [] : scheduledShifts.filter { matches(job: $0.job, note: $0.note, date: $0.startDate) }
        let grouped = Dictionary(grouping: completed) { Calendar.current.dateInterval(of: .month, for: $0.startDate)?.start ?? $0.startDate }
        return ZStack {
            MoneyBackground(mode: .gross)
            List {
                BrandHeader(eyebrow: "Shift history", subtitle: "Completed work and upcoming shifts, all in one place.", mode: .gross, compact: true)
                    .historyListRow(top: 12, bottom: 12)
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Show shifts", selection: $scope) {
                        ForEach(HistoryScope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if jobs.count > 1 {
                        Menu {
                            Picker("Filter by job", selection: $selectedJobID) {
                                Text("All jobs").tag(Optional<UUID>.none)
                                ForEach(jobs) { job in
                                    Text(job.displayName + (job.isArchived ? " · Archived" : "")).tag(Optional(job.id))
                                }
                            }
                        } label: {
                            Label(filterName, systemImage: "line.3.horizontal.decrease")
                                .font(TypeStyle.callout).lineLimit(2)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityLabel("Filter by job: \(filterName)")
                    }
                }
                .tint(theme.grossAccent)
                .historyListRow(bottom: 12)

                if completed.isEmpty && planned.isEmpty {
                    emptyState.historyListRow(top: 12, bottom: 20)
                }
                if !planned.isEmpty {
                    Section {
                        ForEach(planned) { shift in
                            Button { destination = HistoryEditorDestination(kind: .editScheduledShift(shift)) } label: {
                                ScheduledShiftCardView(shift: shift)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Edit this scheduled shift")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { pendingDeletion = .scheduled(shift) }
                            }
                            .historyListRow(bottom: 10)
                        }
                    } header: { Text("Scheduled · \(planned.count)").textCase(nil) }
                }
                ForEach(grouped.keys.sorted(by: >), id: \.self) { month in
                    Section {
                        ForEach(grouped[month] ?? []) { shift in
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
                            .historyListRow(bottom: 10)
                        }
                    } header: { Text(month.formatted(.dateTime.month(.wide).year())).textCase(nil) }
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Log completed shift", systemImage: "plus") { destination = HistoryEditorDestination(kind: .newShift(nil)) }
                    Button("Schedule future shift", systemImage: "calendar.badge.plus") { destination = HistoryEditorDestination(kind: .newScheduledShift(nil)) }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add a completed or scheduled shift")
            }
        }
        .sheet(item: $destination) { destination in
            NavigationStack {
                switch destination.kind {
                case .editShift(let shift): ShiftEditorView(editingShift: shift, availableJobs: jobs.filter { !$0.isArchived || $0.id == shift.job?.id })
                case .newShift(let seed): ShiftEditorView(editingShift: nil, seed: seed, availableJobs: jobs.filter { !$0.isArchived })
                case .editScheduledShift(let shift): ScheduledShiftEditorView(editingShift: shift, availableJobs: jobs.filter { !$0.isArchived })
                case .newScheduledShift(let seed): ScheduledShiftEditorView(editingShift: nil, seed: seed, availableJobs: jobs.filter { !$0.isArchived })
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
                        .buttonStyle(AppActionButtonStyle(accent: theme.grossAccent))
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                if let job = shift.job {
                    JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(job.displayName).font(TypeStyle.title3).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        if job.isArchived { Text("Archived job").font(TypeStyle.caption).foregroundStyle(theme.secondaryText) }
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.tertiaryText)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(shift.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(TypeStyle.callout).foregroundStyle(.white)
                Text(historyTimeRange(start: shift.startDate, end: shift.endDate)).font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
            }
            AdaptiveCardGrid(minimumWidth: 110) {
                earnings("Gross", shift.grossEarnings, accent: theme.grossAccent)
                earnings("Est. take-home", takeHomeEstimate, accent: theme.takeHomeAccent)
            }
            WrappingHStack {
                Label(shift.totalHours.formatted(.number.precision(.fractionLength(0...2))) + " hours", systemImage: "clock")
                if shift.nightHours > 0 { Label(shift.nightHours.formatted(.number.precision(.fractionLength(1))) + " night", systemImage: "moon.stars") }
                if shift.overtimeHours > 0 { Label(shift.overtimeHours.formatted(.number.precision(.fractionLength(1))) + " overtime", systemImage: "bolt") }
            }
            .font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
            if !shift.note.isEmpty {
                Text(shift.note).font(TypeStyle.callout).foregroundStyle(theme.secondaryText).lineLimit(3)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(accent: shift.job?.accent.color ?? theme.grossAccent, hasShadow: false)
        .accessibilityElement(children: .combine)
    }

    private func earnings(_ title: String, _ amount: Double, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(TypeStyle.caption).foregroundStyle(theme.secondaryText)
            Text(amount, format: .currency(code: "USD"))
                .font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(accent)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScheduledShiftCardView: View {
    @Environment(AppTheme.self) private var theme
    let shift: ScheduledShift

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let job = shift.job {
                HStack(spacing: 10) {
                    JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 28)
                    Text(job.displayName).font(TypeStyle.title3).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.tertiaryText)
                }
            }
            Text(shift.startDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(TypeStyle.callout).foregroundStyle(.white)
            Text(historyTimeRange(start: shift.startDate, end: shift.endDate)).font(TypeStyle.callout).foregroundStyle(theme.secondaryText)
            WrappingHStack {
                Label((shift.duration / 3600).formatted(.number.precision(.fractionLength(0...2))) + " hours", systemImage: "clock")
                Label(shift.startDate < .now ? "Review timing" : "Planned", systemImage: shift.startDate < .now ? "exclamationmark.circle" : "calendar")
            }
            .font(TypeStyle.caption).foregroundStyle(theme.takeHomeAccent)
            if !shift.note.isEmpty { Text(shift.note).font(TypeStyle.callout).foregroundStyle(theme.secondaryText).lineLimit(3) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(accent: shift.job?.accent.color ?? theme.takeHomeAccent, hasShadow: false)
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

    init(editingShift: ShiftRecord?, seed: ShiftEditorSeed? = nil, availableJobs: [JobProfile]) {
        self.editingShift = editingShift
        self.availableJobs = availableJobs
        let preferredJob = editingShift?.job?.id ?? seed?.jobIdentifier
        _selectedJobIdentifier = State(initialValue: availableJobs.first(where: { $0.id == preferredJob })?.id ?? availableJobs.first?.id)
        _startDate = State(initialValue: editingShift?.startDate ?? seed?.startDate ?? .now.addingTimeInterval(-8 * 60 * 60))
        _endDate = State(initialValue: editingShift?.endDate ?? seed?.endDate ?? .now)
        _note = State(initialValue: editingShift?.note ?? seed?.note ?? "")
    }

    var body: some View {
        Form {
            Section {
                BrandHeader(
                    eyebrow: editingShift == nil ? "Log Shift" : "Edit Shift",
                    subtitle: "Review the hours and notes saved for this shift.",
                    mode: .gross,
                    compact: true
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section("Timing") {
                if availableJobs.count > 1 {
                    Picker("Job", selection: $selectedJobIdentifier) {
                        ForEach(availableJobs) { job in
                            Text(job.displayName).tag(Optional(job.id))
                        }
                    }
                } else if let job = availableJobs.first {
                    LabeledContent("Job", value: job.displayName)
                }
                DatePicker("Start", selection: $startDate, in: ...Date.now)
                DatePicker("End", selection: $endDate, in: startDate...)
                ShiftDurationSummary(startDate: startDate, endDate: endDate)
                if endDate > .now {
                    AppInlineNotice(message: "Use Schedule Future Shift for planned work.")
                }
            }

            Section("Notes") {
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
        .background(MoneyBackground(mode: .gross))
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

    init(editingShift: ScheduledShift?, seed: ShiftEditorSeed? = nil, availableJobs: [JobProfile]) {
        self.editingShift = editingShift
        self.availableJobs = availableJobs
        let defaultStart = seed?.startDate ?? .now.addingTimeInterval(24 * 60 * 60)
        let defaultEnd = seed?.endDate ?? defaultStart.addingTimeInterval(8 * 60 * 60)
        let preferredJob = editingShift?.job?.id ?? seed?.jobIdentifier
        _selectedJobIdentifier = State(initialValue: availableJobs.first(where: { $0.id == preferredJob })?.id ?? availableJobs.first?.id)
        _startDate = State(initialValue: editingShift?.startDate ?? defaultStart)
        _endDate = State(initialValue: editingShift?.endDate ?? defaultEnd)
        _note = State(initialValue: editingShift?.note ?? seed?.note ?? "")
    }

    var body: some View {
        Form {
            Section {
                BrandHeader(
                    eyebrow: editingShift == nil ? "Schedule Shift" : "Edit Scheduled Shift",
                    subtitle: "Choose the planned start and end for your next shift.",
                    mode: .gross,
                    compact: true
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section("Timing") {
                if availableJobs.count > 1 {
                    Picker("Job", selection: $selectedJobIdentifier) {
                        ForEach(availableJobs) { job in
                            Text(job.displayName).tag(Optional(job.id))
                        }
                    }
                } else if let job = availableJobs.first {
                    LabeledContent("Job", value: job.displayName)
                }
                DatePicker("Start", selection: $startDate)
                DatePicker("End", selection: $endDate, in: startDate...)
                ShiftDurationSummary(startDate: startDate, endDate: endDate)

                Text("The app applies the planned start and end when it is open, or catches up the next time you open it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Notes") {
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
        .background(MoneyBackground(mode: .gross))
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
