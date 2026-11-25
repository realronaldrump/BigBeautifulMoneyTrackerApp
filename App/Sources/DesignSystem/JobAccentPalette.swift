import SwiftUI

extension JobAccentStyle {
    var color: Color {
        switch self {
        case .emerald: TimecardColor.adaptive(light: 0x17634A, dark: 0x8ADCB3)
        case .sky: TimecardColor.blueInk
        case .amber: TimecardColor.adaptive(light: 0x775116, dark: 0xF0C27E)
        case .coral: TimecardColor.redInk
        case .rose: TimecardColor.adaptive(light: 0x92375D, dark: 0xF4A8C3)
        case .slate: TimecardColor.graphite
        }
    }
}
