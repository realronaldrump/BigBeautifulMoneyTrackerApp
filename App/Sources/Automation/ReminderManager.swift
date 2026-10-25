import Foundation
import UserNotifications

@MainActor
final class ReminderManager {
    static let shared = ReminderManager()

    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {}

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func syncShiftReminders(templates: [ScheduleTemplate], isEnabled: Bool) async {
        let activeTemplates = templates.filter { $0.job?.isArchived != true }
        let templateIdentifiers = activeTemplates.map { "template-\($0.id.uuidString)" }
        let pendingIdentifiers = await pendingTemplateIdentifiers()
        guard !Task.isCancelled else { return }
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: Array(Set(templateIdentifiers + pendingIdentifiers))
        )
        guard isEnabled else { return }
        await requestAuthorization()
        guard !Task.isCancelled else { return }

        for template in activeTemplates where template.isEnabled {
            guard !Task.isCancelled else { return }
            let content = UNMutableNotificationContent()
            content.title = "Upcoming shift"
            let prefix = template.job.map { "\($0.displayName): " } ?? ""
            content.body = "\(prefix)\(template.name) starts soon."
            content.sound = .default

            let dateComponents = ReminderSchedule.weeklyComponents(for: template)

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: "template-\(template.id.uuidString)", content: content, trigger: trigger)
            try? await notificationCenter.add(request)
        }
    }

    func syncActiveShiftNotifications(for openShifts: [OpenShiftState]) async {
        guard !Task.isCancelled else { return }
        await cancelActiveShiftNotifications()
        guard openShifts.contains(where: { ($0.scheduledEndDate ?? .distantPast) > .now }) else { return }
        await requestAuthorization()
        guard !Task.isCancelled else { return }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        for openShift in openShifts {
            guard !Task.isCancelled else { return }
            guard let scheduledEndDate = openShift.scheduledEndDate else { continue }
            let endTimeLabel = formatter.string(from: scheduledEndDate)
            let jobPrefix = openShift.job.map { "\($0.displayName): " } ?? ""

            for offset in openShift.scheduledReminderOffsets where offset > 0 {
                let fireDate = scheduledEndDate.addingTimeInterval(TimeInterval(-offset * 60))
                guard fireDate > .now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Shift ending soon"
                content.body = "\(jobPrefix)scheduled to end at \(endTimeLabel)."
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
                content.body = "\(jobPrefix)scheduled to end at \(endTimeLabel)."
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
    }

    func cancelActiveShiftNotifications() async {
        let identifiers = await pendingOpenShiftIdentifiers()
        guard !Task.isCancelled else { return }
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

    private func pendingTemplateIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            notificationCenter.getPendingNotificationRequests { requests in
                let identifiers = requests
                    .map(\.identifier)
                    .filter { $0.hasPrefix("template-") }
                continuation.resume(returning: identifiers)
            }
        }
    }
}
