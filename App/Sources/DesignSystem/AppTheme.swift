import Observation
import SwiftUI

@MainActor
@Observable
final class AppTheme {
    let trueBlack = Color.black
    let panel = Color(red: 0.08, green: 0.09, blue: 0.10)
    let secondaryPanel = Color(red: 0.12, green: 0.13, blue: 0.14)
    let grossAccent = Color(red: 0.28, green: 0.95, blue: 0.49)
    let takeHomeAccent = Color(red: 0.91, green: 0.74, blue: 0.34)
    let secondaryText = Color.white.opacity(0.68)
    let tertiaryText = Color.white.opacity(0.48)

    func accent(for mode: EarningsDisplayMode) -> Color {
        switch mode {
        case .gross:
            grossAccent
        case .takeHome:
            takeHomeAccent
        }
    }

    func glow(for mode: EarningsDisplayMode) -> LinearGradient {
        let accent = accent(for: mode)
        return LinearGradient(
            colors: [accent.opacity(0.45), accent.opacity(0.12), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
