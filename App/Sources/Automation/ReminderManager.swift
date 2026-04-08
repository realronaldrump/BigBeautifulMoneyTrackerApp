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

    func syncActiveShiftNotifications(for openShift: OpenShiftState) async {
        await cancelActiveShiftNotifications()

        guard let scheduledEndDate = openShift.scheduledEndDate else { return }
        await requestAuthorization()

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let endTimeLabel = formatter.string(from: scheduledEndDate)

        for offset in openShift.scheduledReminderOffsets where offset > 0 {
            let fireDate = scheduledEndDate.addingTimeInterval(TimeInterval(-offset * 60))
            guard fireDate > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Shift ending soon"
            content.body = "Your shift is set to end at \(endTimeLabel)."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, fireDate.timeIntervalSinceNow),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "open-shift-\(openShift.id.uuidString)-\(offset)",
                content: content,
                trigger: trigger
            )
            try? await notificationCenter.add(request)
        }

        if scheduledEndDate > .now {
            let content = UNMutableNotificationContent()
            content.title = "Shift end reached"
            content.body = "Your shift was scheduled to end at \(endTimeLabel)."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, scheduledEndDate.timeIntervalSinceNow),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "open-shift-\(openShift.id.uuidString)-end",
                content: content,
                trigger: trigger
            )
            try? await notificationCenter.add(request)
        }
    }

    func cancelActiveShiftNotifications() async {
        let identifiers = await pendingOpenShiftIdentifiers()
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func notifyShiftAutoStopped(at endDate: Date) async {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        let content = UNMutableNotificationContent()
        content.title = "Shift stopped"
        content.body = "This shift was automatically stopped at \(formatter.string(from: endDate))."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "shift-stopped-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await notificationCenter.add(request)
    }

    private func pendingOpenShiftIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            notificationCenter.getPendingNotificationRequests { requests in
                let identifiers = requests
                    .map(\.identifier)
                    .filter { $0.hasPrefix("open-shift-") }
                continuation.resume(returning: identifiers)
            }
        }
    }
}
