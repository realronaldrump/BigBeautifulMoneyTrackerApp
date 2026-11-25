import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Ink on stock, with a separate fixed-color field for the live counter and widgets.
enum TimecardColor {
    static let stock = adaptive(light: 0xF4F1E8, dark: 0x131821)
    static let sheet = adaptive(light: 0xFFFCF3, dark: 0x1C222E)
    static let inset = adaptive(light: 0xE7E3D7, dark: 0x2A303C)
    static let ink = adaptive(light: 0x192237, dark: 0xF3F1E8)
    static let graphite = adaptive(light: 0x515766, dark: 0xB7BBC8)
    static let rule = adaptive(light: 0xB9B9B1, dark: 0x495263)
    static let blueInk = adaptive(light: 0x233EAB, dark: 0xA4B6FF)
    static let redInk = adaptive(light: 0xA2331D, dark: 0xFFAE96)
    static let cobalt = Color(red: 0.113, green: 0.216, blue: 0.628)
    static let vermilion = Color(red: 0.678, green: 0.216, blue: 0.123)
    static let chalk = Color(red: 1, green: 0.986, blue: 0.935)

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
        #else
        Color(red: Double((light >> 16) & 255) / 255,
              green: Double((light >> 8) & 255) / 255, blue: Double(light & 255) / 255)
        #endif
    }
}

enum TimecardType {
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom("BarlowCondensed-Bold", size: size, relativeTo: style)
    }
    static let label: Font = .system(.caption, design: .monospaced, weight: .semibold)
}
