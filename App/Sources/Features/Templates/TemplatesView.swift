import SwiftData
import SwiftUI

struct TemplatesView: View {
    @Environment(AppTheme.self) private var theme

    @Query(sort: \ScheduleTemplate.weekdayRawValue) private var templates: [ScheduleTemplate]
    @Query(sort: \JobProfile.sortOrder) private var jobs: [JobProfile]
    @Query private var preferences: [AppPreferences]

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
                        subtitle: selectedJobName == nil
                            ? "Build repeating shifts for one or many jobs and keep reminders and projections ready."
                            : "Build repeating shifts for \(selectedJobName!).",
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
        .onDisappear {
            Task {
                await ReminderManager.shared.syncShiftReminders(
                    templates: templates,
                    isEnabled: preferences.first?.remindersEnabled ?? false
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No templates yet")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Build a repeating shift once, and the app can keep reminders and projections ready for the right job.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 72)
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

            TextField("Template name", text: $name)
            Picker("Weekday", selection: $weekday) {
                ForEach(ScheduleWeekday.allCases) { weekday in
                    Text(weekday.title).tag(weekday)
                }
            }
            DatePicker("Start time", selection: startTimeBinding, displayedComponents: .hourAndMinute)
            DatePicker("End time", selection: endTimeBinding, displayedComponents: .hourAndMinute)
            Stepper("Reminder: \(reminderMinutesBefore) min before", value: $reminderMinutesBefore, in: 0...180, step: 5)
            Toggle("Enabled", isOn: $isEnabled)
        }
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
                .disabled(resolvedJob == nil)
            }
        }
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
            editingTemplate.name = name
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
                    name: name,
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
        try? modelContext.save()
        dismiss()
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
                                .font(.system(size: 12, weight: .bold, design: .rounded))
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
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)

            HStack(spacing: 10) {
                Label("\(template.reminderMinutesBefore) min reminder", systemImage: "bell.badge")
                Label(template.isEnabled ? "Enabled" : "Paused", systemImage: template.isEnabled ? "checkmark.circle" : "pause.circle")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(template.isEnabled ? theme.takeHomeAccent : theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: template.job?.accent.color ?? .white)
    }
}

private func templateTimeLabel(hour: Int, minute: Int) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    return formatter.string(from: date)
}
