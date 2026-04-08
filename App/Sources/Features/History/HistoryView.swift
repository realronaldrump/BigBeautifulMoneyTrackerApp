import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppTheme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ShiftRecord.startDate, order: .reverse) private var shifts: [ShiftRecord]
    @Query private var paySchedules: [PaySchedule]
    @Query private var taxProfiles: [TaxProfile]
    @Query private var payRates: [PayRateSchedule]
    @Query private var templates: [ScheduleTemplate]

    @State private var editingShift: ShiftRecord?
    @State private var creatingShift = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if shifts.isEmpty {
                    emptyState
                } else {
                    ForEach(shifts) { shift in
                        Button {
                            editingShift = shift
                        } label: {
                            ShiftCardView(shift: shift, takeHomeEstimate: takeHomeEstimate(for: shift))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingShift = shift
                            } label: {
                                Label("Edit Shift", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                try? ShiftController.deleteShift(shift, in: modelContext)
                            } label: {
                                Label("Delete Shift", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creatingShift = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingShift) { shift in
            NavigationStack {
                ShiftEditorView(editingShift: shift)
            }
        }
        .sheet(isPresented: $creatingShift) {
            NavigationStack {
                ShiftEditorView(editingShift: nil)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No shifts yet")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Completed shifts land here automatically. Manual corrections stay secondary, but they’re ready whenever you need them.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 120)
    }

    private func takeHomeEstimate(for shift: ShiftRecord) -> Double {
        guard
            let paySchedule = paySchedules.first,
            let taxProfile = taxProfiles.first
        else {
            return shift.grossEarnings
        }

        let currentRate = payRates.max(by: { $0.effectiveDate < $1.effectiveDate })?.hourlyRate ?? 0
        let ytdGross = AggregationService.totalGross(for: shifts.filter {
            Calendar.current.isDate($0.startDate, equalTo: shift.startDate, toGranularity: .year)
        })

        let estimate = TaxEstimator.estimate(
            currentGross: 0,
            yearToDateGrossExcludingCurrentShift: ytdGross,
            payFrequency: paySchedule.frequency,
            taxProfile: taxProfile,
            currentHourlyRate: currentRate,
            templates: templates
        )

        return TaxEstimator.estimatedTakeHome(for: shift.grossEarnings, estimate: estimate)
    }
}

private struct ShiftCardView: View {
    @Environment(AppTheme.self) private var theme

    let shift: ShiftRecord
    let takeHomeEstimate: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
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
                        .font(.system(size: 24, weight: .bold, design: .rounded))
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
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.panel.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

struct ShiftEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let editingShift: ShiftRecord?

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var note: String
    @State private var errorText: String?

    init(editingShift: ShiftRecord?) {
        self.editingShift = editingShift
        _startDate = State(initialValue: editingShift?.startDate ?? .now.addingTimeInterval(-8 * 60 * 60))
        _endDate = State(initialValue: editingShift?.endDate ?? .now)
        _note = State(initialValue: editingShift?.note ?? "")
    }

    var body: some View {
        Form {
            Section("Timing") {
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
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(editingShift == nil ? "Manual Shift" : "Edit Shift")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    do {
                        try ShiftController.saveManualShift(
                            in: modelContext,
                            editing: editingShift,
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
