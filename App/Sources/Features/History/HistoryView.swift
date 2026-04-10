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
    @State private var deleteErrorText: String?

    var body: some View {
        ZStack {
            MoneyBackground(mode: .gross)

            List {
                    BrandHeader(
                        eyebrow: "Shift History",
                        subtitle: "Review completed shifts, schedule future work, and keep a personal earnings ledger.",
                        mode: .gross,
                        compact: true
                    )
                .historyListRow(top: 18, bottom: 12)

                if scheduledShifts.isEmpty, shifts.isEmpty {
                    emptyState
                        .historyListRow(top: 24, bottom: 12)
                }

                if !scheduledShifts.isEmpty {
                    sectionHeader(title: "Upcoming Schedule", systemImage: "calendar.badge.clock")
                        .historyListRow(top: 8, bottom: 6)

                    ForEach(scheduledShifts) { shift in
                        Button {
                            destination = HistoryEditorDestination(kind: .editScheduledShift(shift))
                        } label: {
                            ScheduledShiftCardView(shift: shift)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteScheduledShift(shift)
                            } label: {
                                Label("Delete Schedule", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                destination = HistoryEditorDestination(kind: .editScheduledShift(shift))
                            } label: {
                                Label("Edit Schedule", systemImage: "calendar")
                            }

                            Button(role: .destructive) {
                                deleteScheduledShift(shift)
                            } label: {
                                Label("Delete Schedule", systemImage: "trash")
                            }
                        }
                        .historyListRow(bottom: 8)
                    }
                }

                if !shifts.isEmpty {
                    sectionHeader(title: "Completed Shifts", systemImage: "clock.arrow.circlepath")
                        .historyListRow(top: scheduledShifts.isEmpty ? 8 : 18, bottom: 6)

                    ForEach(shifts) { shift in
                        Button {
                            destination = HistoryEditorDestination(kind: .editShift(shift))
                        } label: {
                            ShiftCardView(
                                shift: shift,
                                takeHomeEstimate: takeHomeEstimate(for: shift),
                                bestShiftGross: shifts.map(\.grossEarnings).max() ?? 0
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteShift(shift)
                            } label: {
                                Label("Delete Shift", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                destination = HistoryEditorDestination(kind: .editShift(shift))
                            } label: {
                                Label("Edit Shift", systemImage: "pencil")
                            }

                            Button {
                                destination = HistoryEditorDestination(
                                    kind: .newShift(ShiftEditorSeed.duplicate(from: shift))
                                )
                            } label: {
                                Label("Duplicate Shift", systemImage: "doc.on.doc")
                            }

                            Button {
                                destination = HistoryEditorDestination(
                                    kind: .newScheduledShift(ShiftEditorSeed.scheduledCopy(from: shift))
                                )
                            } label: {
                                Label("Schedule Again", systemImage: "calendar.badge.plus")
                            }

                            Button(role: .destructive) {
                                deleteShift(shift)
                            } label: {
                                Label("Delete Shift", systemImage: "trash")
                            }
                        }
                        .historyListRow(bottom: 8)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaPadding(.bottom, 120)
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        destination = HistoryEditorDestination(kind: .newShift(nil))
                    } label: {
                        Label("Log Completed Shift", systemImage: "plus")
                    }

                    Button {
                        destination = HistoryEditorDestination(kind: .newScheduledShift(nil))
                    } label: {
                        Label("Schedule Future Shift", systemImage: "calendar.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $destination) { destination in
            NavigationStack {
                switch destination.kind {
                case .editShift(let shift):
                    ShiftEditorView(editingShift: shift, availableJobs: jobs.filter { !$0.isArchived })
                case .newShift(let seed):
                    ShiftEditorView(editingShift: nil, seed: seed, availableJobs: jobs.filter { !$0.isArchived })
                case .editScheduledShift(let shift):
                    ScheduledShiftEditorView(editingShift: shift, availableJobs: jobs.filter { !$0.isArchived })
                case .newScheduledShift(let seed):
                    ScheduledShiftEditorView(editingShift: nil, seed: seed, availableJobs: jobs.filter { !$0.isArchived })
                }
            }
        }
        .alert("Unable to Delete Entry", isPresented: deleteErrorIsPresented) {
            Button("OK", role: .cancel) {
                deleteErrorText = nil
            }
        } message: {
            Text(deleteErrorText ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No shifts yet")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Completed shifts land here automatically, and future shifts can live here before they start.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 72)
    }

    private func sectionHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.top, 8)
    }

    private func takeHomeEstimate(for shift: ShiftRecord) -> Double {
        guard let taxProfile = taxProfiles.first else {
            return shift.grossEarnings
        }

        return TaxEstimator.estimatedTakeHome(
            for: shift,
            allShifts: shifts,
            payRates: payRates,
            paySchedules: paySchedules,
            templates: templates,
            taxProfile: taxProfile,
            calendar: Calendar.current
        )
    }

    private var deleteErrorIsPresented: Binding<Bool> {
        Binding(
            get: { deleteErrorText != nil },
            set: { isPresented in
                if !isPresented {
                    deleteErrorText = nil
                }
            }
        )
    }

    private func deleteShift(_ shift: ShiftRecord) {
        do {
            try ShiftController.deleteShift(shift, in: modelContext)
        } catch {
            deleteErrorText = error.localizedDescription
        }
    }

    private func deleteScheduledShift(_ shift: ScheduledShift) {
        do {
            try ShiftController.deleteScheduledShift(shift, in: modelContext)
        } catch {
            deleteErrorText = error.localizedDescription
        }
    }
}

private extension View {
    func historyListRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 18, bottom: bottom, trailing: 18))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private struct ShiftCardView: View {
    @Environment(AppTheme.self) private var theme

    let shift: ShiftRecord
    let takeHomeEstimate: Double
    var bestShiftGross: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let job = shift.job {
                        HStack(spacing: Spacing.sm) {
                            JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 22)
                            Text(job.displayName)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(job.accent.color)
                        }
                    }

                    Text(shift.startDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("\(shift.startDate.formatted(date: .omitted, time: .shortened)) - \(shift.endDate.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    Text(shift.grossEarnings, format: .currency(code: "USD"))
                        .font(TypeStyle.title)
                        .foregroundStyle(theme.grossAccent)
                    Text(takeHomeEstimate, format: .currency(code: "USD"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.takeHomeAccent)
                }
            }

            HStack {
                Label("\(shift.totalHours.formatted(.number.precision(.fractionLength(2)))) hrs", systemImage: "clock")
                Spacer()
                Label("\(shift.regularHours.formatted(.number.precision(.fractionLength(1)))) reg", systemImage: "sun.max")
                Spacer()
                Label("\(shift.nightHours.formatted(.number.precision(.fractionLength(1)))) night", systemImage: "moon.stars")
                Spacer()
                Label("\(shift.overtimeHours.formatted(.number.precision(.fractionLength(1)))) OT", systemImage: "sparkles")
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(theme.secondaryText)

            // Earnings bar — width relative to best shift
            if bestShiftGross > 0 {
                GeometryReader { geometry in
                    let fraction = min(shift.grossEarnings / bestShiftGross, 1.0)
                    let barColor = shift.job?.accent.color ?? theme.grossAccent
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(barColor.opacity(0.5))
                        .frame(width: geometry.size.width * fraction, height: 4)
                }
                .frame(height: 4)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: shift.job?.accent.color ?? theme.grossAccent)
    }
}

private struct ScheduledShiftCardView: View {
    @Environment(AppTheme.self) private var theme

    let shift: ScheduledShift

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let job = shift.job {
                        HStack(spacing: Spacing.sm) {
                            JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 22)
                            Text(job.displayName)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(job.accent.color)
                        }
                    }

                    Text(shift.startDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("\(shift.startDate.formatted(date: .omitted, time: .shortened)) - \(shift.endDate.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()

                Text("Auto")
                    .font(TypeStyle.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, Spacing.sm)
                    .background(theme.takeHomeAccent)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label(
                    "\(shift.duration / 3600, format: .number.precision(.fractionLength(2))) hrs",
                    systemImage: "clock"
                )

                HStack(spacing: 12) {
                    Label("Auto start", systemImage: "play.circle")
                    Label("Auto stop", systemImage: "stop.circle")
                }
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(theme.secondaryText)

            if !shift.note.isEmpty {
                Text(shift.note)
                    .font(TypeStyle.caption)
                    .foregroundStyle(Color.white.opacity(0.88))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: shift.job?.accent.color ?? .white)
    }
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

    init(editingShift: ShiftRecord?, seed: ShiftEditorSeed? = nil, availableJobs: [JobProfile]) {
        self.editingShift = editingShift
        self.availableJobs = availableJobs
        _selectedJobIdentifier = State(initialValue: editingShift?.job?.id ?? seed?.jobIdentifier ?? availableJobs.first?.id)
        _startDate = State(initialValue: editingShift?.startDate ?? seed?.startDate ?? .now.addingTimeInterval(-8 * 60 * 60))
        _endDate = State(initialValue: editingShift?.endDate ?? seed?.endDate ?? .now)
        _note = State(initialValue: editingShift?.note ?? seed?.note ?? "")
    }

    var body: some View {
        Form {
            Section {
                BrandHeader(
                    eyebrow: editingShift == nil ? "Log Shift" : "Edit Shift",
                    subtitle: "Adjust timing and notes for your own work history without losing the clean ledger.",
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
                }
                DatePicker("Start", selection: $startDate)
                DatePicker("End", selection: $endDate, in: startDate...)
            }

            Section("Notes") {
                TextField("Optional note", text: $note, axis: .vertical)
            }

            if let editingShift {
                Section {
                    Button(role: .destructive) {
                        do {
                            try ShiftController.deleteShift(editingShift, in: modelContext)
                            dismiss()
                        } catch {
                            errorText = error.localizedDescription
                        }
                    } label: {
                        Text("Delete this shift")
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
        .navigationTitle(editingShift == nil ? "Log Shift" : "Edit Shift")
        .navigationBarTitleDisplayMode(.inline)
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

    init(editingShift: ScheduledShift?, seed: ShiftEditorSeed? = nil, availableJobs: [JobProfile]) {
        self.editingShift = editingShift
        self.availableJobs = availableJobs
        let defaultStart = seed?.startDate ?? .now.addingTimeInterval(24 * 60 * 60)
        let defaultEnd = seed?.endDate ?? defaultStart.addingTimeInterval(8 * 60 * 60)
        _selectedJobIdentifier = State(initialValue: editingShift?.job?.id ?? seed?.jobIdentifier ?? availableJobs.first?.id)
        _startDate = State(initialValue: editingShift?.startDate ?? defaultStart)
        _endDate = State(initialValue: editingShift?.endDate ?? defaultEnd)
        _note = State(initialValue: editingShift?.note ?? seed?.note ?? "")
    }

    var body: some View {
        Form {
            Section {
                BrandHeader(
                    eyebrow: editingShift == nil ? "Schedule Shift" : "Edit Scheduled Shift",
                    subtitle: "Plan future shifts for your own schedule and let the app start and stop them automatically.",
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
                }
                DatePicker("Start", selection: $startDate)
                DatePicker("End", selection: $endDate, in: startDate...)

                Text("When the start time arrives, this shift opens automatically and uses the end time for auto-stop.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Notes") {
                TextField("Optional note", text: $note, axis: .vertical)
            }

            if let editingShift {
                Section {
                    Button(role: .destructive) {
                        do {
                            try ShiftController.deleteScheduledShift(editingShift, in: modelContext)
                            dismiss()
                        } catch {
                            errorText = error.localizedDescription
                        }
                    } label: {
                        Text("Delete this scheduled shift")
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
        .navigationTitle(editingShift == nil ? "Schedule Shift" : "Edit Scheduled Shift")
        .navigationBarTitleDisplayMode(.inline)
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
            }
        }
    }
}
