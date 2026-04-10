import SwiftUI

extension JobAccentStyle {
    var color: Color {
        switch self {
        case .emerald:
            Color(red: 0.31, green: 0.83, blue: 0.57)
        case .sky:
            Color(red: 0.38, green: 0.73, blue: 0.98)
        case .amber:
            Color(red: 0.98, green: 0.74, blue: 0.26)
        case .coral:
            Color(red: 0.98, green: 0.54, blue: 0.43)
        case .rose:
            Color(red: 0.96, green: 0.47, blue: 0.66)
        case .slate:
            Color(red: 0.67, green: 0.73, blue: 0.82)
        }
    }
}
