import SwiftUI

struct MilestoneBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .default, weight: .semibold))
            .foregroundStyle(TimecardColor.chalk)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(TimecardColor.cobalt)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
