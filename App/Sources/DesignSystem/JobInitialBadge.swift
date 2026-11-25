import SwiftUI

struct JobInitialBadge: View {
    let name: String
    let accent: Color
    var size: CGFloat = 28

    var body: some View {
        Text(name.prefix(1).uppercased())
            .font(TimecardType.display(size * 0.72, relativeTo: .headline))
            .lineLimit(1).minimumScaleFactor(0.5)
            .foregroundStyle(accent)
            .frame(width: size, height: size)
            .overlay { Rectangle().strokeBorder(accent, lineWidth: 1.5) }
            .accessibilityHidden(true)
    }
}
