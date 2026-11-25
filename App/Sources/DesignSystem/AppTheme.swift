import Observation
import SwiftUI

// MARK: - Design Tokens

enum CornerRadius {
    static let cardLarge: CGFloat = 6
    static let cardSmall: CGFloat = 3
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
}

enum TypeStyle {
    static let headline = TimecardType.display(48, relativeTo: .largeTitle)
    static let title = TimecardType.display(34, relativeTo: .title)
    static let title2 = TimecardType.display(26, relativeTo: .title2)
    static let title3 = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let caption = Font.footnote
    static let micro = TimecardType.label
}

// MARK: - Theme

@MainActor
@Observable
final class AppTheme {
    static let brandName = "Davis's Big Beautiful Money Tracker App"

    let grossAccent = TimecardColor.blueInk
    let takeHomeAccent = TimecardColor.blueInk
    let stopAccent = TimecardColor.redInk
    let secondaryText = TimecardColor.graphite
    let tertiaryText = TimecardColor.graphite

    func accent(for mode: EarningsDisplayMode) -> Color {
        switch mode {
        case .gross:
            grossAccent
        case .takeHome:
            takeHomeAccent
        }
    }
}

struct BrandSignature: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("BrandLogo").resizable().scaledToFit().frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
            Text(AppTheme.brandName).font(TypeStyle.callout).foregroundStyle(.secondary)
        }
    }
}
