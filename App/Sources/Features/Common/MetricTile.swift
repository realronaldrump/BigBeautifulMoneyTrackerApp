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
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CornerRadius.cardSmall)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: CornerRadius.cardSmall))
        .accessibilityElement(children: .combine)
    }
}
