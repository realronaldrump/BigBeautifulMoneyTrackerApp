import SwiftUI

struct MilestoneBanner: View {
    @Environment(AppTheme.self) private var theme

    let text: String
    let mode: EarningsDisplayMode

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(theme.accent(for: mode))
            .clipShape(Capsule())
            .shadow(color: theme.accent(for: mode).opacity(0.4), radius: 20)
    }
}
