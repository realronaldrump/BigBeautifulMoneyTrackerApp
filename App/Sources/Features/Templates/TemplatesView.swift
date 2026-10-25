import SwiftData
import SwiftUI

struct TemplatesView: View {
    @Environment(AppTheme.self) private var theme

    @Query(sort: \ScheduleTemplate.weekdayRawValue) private var templates: [ScheduleTemplate]
    @Query(sort: \JobProfile.sortOrder) private var jobs: [JobProfile]

    @State private var editingTemplate: ScheduleTemplate?
    @State private var creatingTemplate = false

    let selectedJobID: UUID?

    init(selectedJobID: UUID? = nil) {
        self.selectedJobID = selectedJobID
    }

    private var activeJobs: [JobProfile] {
        jobs.filter { !$0.isArchived }
    }

    private var displayedTemplates: [ScheduleTemplate] {
        templates.filter { template in
            guard template.job?.isArchived != true else { return false }
            guard let selectedJobID else { return true }
            return template.job?.id == selectedJobID
        }
    }

    private var selectedJobName: String? {
        guard let selectedJobID else { return nil }
        return activeJobs.first(where: { $0.id == selectedJobID })?.displayName
    }

    var body: some View {
        ZStack {
            MoneyBackground(mode: .gross)

            ScrollView {
                LazyVStack(spacing: 14) {
                    BrandHeader(
                        eyebrow: selectedJobName ?? "Schedule Templates",
                        subtitle: selectedJobName.map { "Repeating work for \($0), used in projections and reminders." }
                            ?? "Repeating shifts for paycheck projections and weekly reminders.",
                        mode: .gross,
                        compact: true
                    )

                    if displayedTemplates.isEmpty {
                        emptyState
                    } else {
                        ForEach(displayedTemplates) { template in
                            Button {
                                editingTemplate = template
                            } label: {
                                TemplateCardView(template: template)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle(selectedJobName ?? "Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creatingTemplate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add schedule template")
                .disabled(activeJobs.isEmpty)
            }
        }
        .sheet(item: $editingTemplate) { template in
            NavigationStack {
                TemplateEditorView(
                    editingTemplate: template,
                    preselectedJobID: selectedJobID,
                    availableJobs: activeJobs
                )
            }
        }
        .sheet(isPresented: $creatingTemplate) {
            NavigationStack {
                TemplateEditorView(
                    editingTemplate: nil,
                    preselectedJobID: selectedJobID,
                    availableJobs: activeJobs
                )
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Plan your usual week", systemImage: "calendar.badge.plus")
        } description: {
            Text("Create a template for a shift you work regularly. Templates help forecast pay and remind you before work.")
        } actions: {
            Button("Add a template") { creatingTemplate = true }
                .buttonStyle(AppActionButtonStyle(accent: theme.grossAccent))
                .disabled(activeJobs.isEmpty)
        }
    }
}

private struct TemplateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let editingTemplate: ScheduleTemplate?
    let preselectedJobID: UUID?
    let availableJobs: [JobProfile]

    @State private var selectedJobID: UUID?
    @State private var name: String
    @State private var weekday: ScheduleWeekday
    @State private var startHour: Int
    @State private var startMinute: Int
    @State private var endHour: Int
    @State private var endMinute: Int
    @State private var reminderMinutesBefore: Int
    @State private var isEnabled: Bool
    @State private var errorText: String?
    @State private var confirmingDeletion = false

    init(editingTemplate: ScheduleTemplate?, preselectedJobID: UUID?, availableJobs: [JobProfile]) {
        self.editingTemplate = editingTemplate
        self.preselectedJobID = preselectedJobID
        self.availableJobs = availableJobs
        _selectedJobID = State(initialValue: editingTemplate?.job?.id ?? preselectedJobID ?? availableJobs.first?.id)
        _name = State(initialValue: editingTemplate?.name ?? "Standard Shift")
        _weekday = State(initialValue: editingTemplate?.weekday ?? .monday)
        _startHour = State(initialValue: editingTemplate?.startHour ?? 7)
        _startMinute = State(initialValue: editingTemplate?.startMinute ?? 0)
        _endHour = State(initialValue: editingTemplate?.endHour ?? 19)
        _endMinute = State(initialValue: editingTemplate?.endMinute ?? 0)
        _reminderMinutesBefore = State(initialValue: editingTemplate?.reminderMinutesBefore ?? 30)
        _isEnabled = State(initialValue: editingTemplate?.isEnabled ?? true)
    }

    var body: some View {
        Form {
            Section {
                BrandHeader(
                    eyebrow: editingTemplate == nil ? "New Template" : "Edit Template",
                    subtitle: "Shape repeating shifts and reminder timing for the correct job.",
                    mode: .gross,
                    compact: true
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            }

            if preselectedJobID == nil {
                Section("Job") {
                    Picker("Template belongs to", selection: $selectedJobID) {
                        ForEach(availableJobs) { job in
                            Text(job.displayName).tag(Optional(job.id))
                        }
                    }
                }
            }

            Section("Template") {
                TextField("Template name", text: $name).textInputAutocapitalization(.words)
                Picker("Weekday", selection: $weekday) {
                    ForEach(ScheduleWeekday.allCases) { weekday in Text(weekday.title).tag(weekday) }
                }
            }
            Section("Shift timing") {
                DatePicker("Start time", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                DatePicker("End time", selection: endTimeBinding, displayedComponents: .hourAndMinute)
                if scheduledMinutes > 0 {
                    AppValueRow(title: "Scheduled duration", value: (Double(scheduledMinutes) / 60).formatted(.number.precision(.fractionLength(0...2))) + " hours")
                    if endHour * 60 + endMinute < startHour * 60 + startMinute {
                        Label("Ends the next day", systemImage: "moon.stars").font(TypeStyle.caption).foregroundStyle(.secondary)
                    }
                } else {
                    AppInlineNotice(message: "Choose different start and end times.")
                }
            }
            Section {
                Stepper(reminderMinutesBefore == 0 ? "At shift start" : "\(reminderMinutesBefore) minutes before", value: $reminderMinutesBefore, in: 0...180, step: 5)
                Toggle("Use this template", isOn: $isEnabled)
            } header: { Text("Planning & reminders") } footer: {
                Text("Templates inform projections and weekly reminders. They do not start a tracked shift.")
            }
            if editingTemplate != nil {
                Section {
                    Button("Delete template", role: .destructive) { confirmingDeletion = true }
                }
            }
            if let errorText { Section { AppInlineNotice(message: errorText) } }
        }
        .appKeyboardToolbar()
        .confirmationDialog("Delete template?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Delete template", role: .destructive) {
                guard let editingTemplate else { return }
                do {
                    modelContext.delete(editingTemplate)
                    try PersistenceService.save(modelContext)
                    dismiss()
                } catch { errorText = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Future reminders and projections will no longer include this template.") }
        .navigationTitle(editingTemplate == nil ? "New Template" : "Edit Template")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(MoneyBackground(mode: .gross))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(resolvedJob == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (startHour == endHour && startMinute == endMinute))
            }
        }
    }

    private var scheduledMinutes: Int {
        let start = startHour * 60 + startMinute
        let end = endHour * 60 + endMinute
        return end >= start ? end - start : 1440 - start + end
    }

    private var resolvedJob: JobProfile? {
        availableJobs.first(where: { $0.id == selectedJobID })
    }

    private func save() {
        guard let resolvedJob else {
            return
        }

        if let editingTemplate {
            editingTemplate.job = resolvedJob
            editingTemplate.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            editingTemplate.weekday = weekday
            editingTemplate.startHour = startHour
            editingTemplate.startMinute = startMinute
            editingTemplate.endHour = endHour
            editingTemplate.endMinute = endMinute
            editingTemplate.reminderMinutesBefore = reminderMinutesBefore
            editingTemplate.isEnabled = isEnabled
        } else {
            modelContext.insert(
                ScheduleTemplate(
                    job: resolvedJob,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    weekday: weekday,
                    startHour: startHour,
                    startMinute: startMinute,
                    endHour: endHour,
                    endMinute: endMinute,
                    reminderMinutesBefore: reminderMinutesBefore,
                    isEnabled: isEnabled
                )
            )
        }
        do {
            try PersistenceService.save(modelContext)
            dismiss()
        } catch {
            modelContext.rollback()
            errorText = error.localizedDescription
        }
    }

    private var startTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: startHour, minute: startMinute)) ?? .now
            },
            set: { newValue in
                startHour = Calendar.current.component(.hour, from: newValue)
                startMinute = Calendar.current.component(.minute, from: newValue)
            }
        )
    }

    private var endTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: endHour, minute: endMinute)) ?? .now
            },
            set: { newValue in
                endHour = Calendar.current.component(.hour, from: newValue)
                endMinute = Calendar.current.component(.minute, from: newValue)
            }
        )
    }
}

private struct TemplateCardView: View {
    @Environment(AppTheme.self) private var theme

    let template: ScheduleTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if let job = template.job {
                        HStack(spacing: Spacing.sm) {
                            JobInitialBadge(name: job.displayName, accent: job.accent.color, size: 22)
                            Text(job.displayName)
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(job.accent.color)
                        }
                    }

                    Text(template.name)
                        .font(TypeStyle.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }

                Spacer()
            }

            Text("\(template.weekday.title) • \(templateTimeLabel(hour: template.startHour, minute: template.startMinute)) - \(templateTimeLabel(hour: template.endHour, minute: template.endMinute))")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(theme.secondaryText)

            WrappingHStack {
                Label(template.reminderMinutesBefore == 0 ? "Reminder at start" : "\(template.reminderMinutesBefore) min before", systemImage: "bell.badge")
                Label(template.isEnabled ? "Enabled" : "Paused", systemImage: template.isEnabled ? "checkmark.circle" : "pause.circle")
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(template.isEnabled ? theme.takeHomeAccent : theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: template.job?.accent.color ?? .white, hasShadow: false)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit template timing and reminders")
    }
}

private func templateTimeLabel(hour: Int, minute: Int) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    return formatter.string(from: date)
}
