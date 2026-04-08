import Foundation
import UserNotifications

@MainActor
final class ReminderManager {
    static let shared = ReminderManager()

    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {}

    func requestAuthorization() async {
        _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func syncShiftReminders(templates: [ScheduleTemplate], isEnabled: Bool) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: templates.map { "template-\($0.id.uuidString)" })
        guard isEnabled else { return }

        for template in templates where template.isEnabled {
            let content = UNMutableNotificationContent()
            content.title = "Upcoming shift"
            content.body = "Your \(template.name) shift starts soon."
            content.sound = .default

            var dateComponents = DateComponents()
            dateComponents.weekday = template.weekday.rawValue
            dateComponents.hour = template.startHour
            dateComponents.minute = max(0, template.startMinute - template.reminderMinutesBefore)

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: "template-\(template.id.uuidString)", content: content, trigger: trigger)
            try? await notificationCenter.add(request)
        }
    }
}
