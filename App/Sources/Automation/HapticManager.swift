import SwiftUI
import UIKit

@MainActor
final class HapticManager {
    static let shared = HapticManager()

    enum HapticType {
        case selection
        case action
        case success
    }

    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init() {
        selectionGenerator.prepare()
        impactGenerator.prepare()
        notificationGenerator.prepare()
    }

    func fire(_ type: HapticType, enabled: Bool) {
        guard enabled else { return }

        switch type {
        case .selection:
            selectionGenerator.selectionChanged()
        case .action:
            impactGenerator.impactOccurred(intensity: 0.82)
        case .success:
            notificationGenerator.notificationOccurred(.success)
        }
    }
}
