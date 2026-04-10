import SwiftUI

struct MetricTile: View {
    @Environment(AppTheme.self) private var theme

    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title.uppercased())
                .font(TypeStyle.micro)
                .tracking(1.2)
                .foregroundStyle(theme.tertiaryText)

            Text(value)
                .font(TypeStyle.title2)
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CornerRadius.cardSmall)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: accent)
    }
}

