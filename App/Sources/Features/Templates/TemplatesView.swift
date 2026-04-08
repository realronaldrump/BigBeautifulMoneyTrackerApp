import SwiftData
import SwiftUI

struct TemplatesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ScheduleTemplate.weekdayRawValue) private var templates: [ScheduleTemplate]
    @Query private var preferences: [AppPreferences]

    @State private var editingTemplate: ScheduleTemplate?
    @State private var creatingTemplate = false

    var body: some View {
        List {
            ForEach(templates) { template in
                Button {
                    editingTemplate = template
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(template.name)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text("\(template.weekday.title) • \(String(format: "%02d:%02d", template.startHour, template.startMinute)) - \(String(format: "%02d:%02d", template.endHour, template.endMinute))")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creatingTemplate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingTemplate) { template in
            NavigationStack { TemplateEditorView(editingTemplate: template) }
        }
        .sheet(isPresented: $creatingTemplate) {
            NavigationStack { TemplateEditorView(editingTemplate: nil) }
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
}

private struct TemplateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let editingTemplate: ScheduleTemplate?

    @State private var name: String
    @State private var weekday: ScheduleWeekday
    @State private var startHour: Int
    @State private var startMinute: Int
    @State private var endHour: Int
    @State private var endMinute: Int
    @State private var reminderMinutesBefore: Int
    @State private var isEnabled: Bool

    init(editingTemplate: ScheduleTemplate?) {
        self.editingTemplate = editingTemplate
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
            TextField("Template name", text: $name)
            Picker("Weekday", selection: $weekday) {
                ForEach(ScheduleWeekday.allCases) { weekday in
                    Text(weekday.title).tag(weekday)
                }
            }
            Stepper("Start hour: \(startHour):\(String(format: "%02d", startMinute))", value: $startHour, in: 0...23)
            Stepper("End hour: \(endHour):\(String(format: "%02d", endMinute))", value: $endHour, in: 0...23)
            Stepper("Reminder: \(reminderMinutesBefore) min before", value: $reminderMinutesBefore, in: 0...180, step: 5)
            Toggle("Enabled", isOn: $isEnabled)
        }
        .navigationTitle(editingTemplate == nil ? "New Template" : "Edit Template")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if let editingTemplate {
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
            }
        }
    }
}
