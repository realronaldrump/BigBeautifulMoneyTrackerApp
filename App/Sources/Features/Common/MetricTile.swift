import SwiftUI

struct MetricTile: View {
    @Environment(AppTheme.self) private var theme

    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(TypeStyle.micro)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(theme.tertiaryText)

            Text(value)
                .font(TimecardType.display(28, relativeTo: .title2))
                .monospacedDigit()
                .foregroundStyle(TimecardColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(accent.opacity(0.3)).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}
