import Foundation

enum ReminderSchedule {
    static func weeklyComponents(for template: ScheduleTemplate, calendar: Calendar = .current) -> DateComponents {
        // Use a real week so subtraction carries through midnight and Sunday.
        let reference = calendar.date(from: DateComponents(year: 2026, month: 1, day: 4)) ?? .now
        let day = calendar.date(byAdding: .day, value: template.weekday.rawValue - 1, to: reference) ?? reference
        let start = calendar.date(bySettingHour: template.startHour, minute: template.startMinute, second: 0, of: day) ?? day
        let reminder = calendar.date(byAdding: .minute, value: -max(0, template.reminderMinutesBefore), to: start) ?? start
        return calendar.dateComponents([.weekday, .hour, .minute], from: reminder)
    }
}
