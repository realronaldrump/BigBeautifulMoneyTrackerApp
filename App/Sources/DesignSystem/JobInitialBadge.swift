import SwiftUI

/// A consistent job-identity badge that replaces the plain colored dot across the entire app.
/// Shows the job's first initial inside a tinted circle, sized for inline or header contexts.
struct JobInitialBadge: View {
    let name: String
    let accent: Color
    var size: CGFloat = 28

    private var fontSize: CGFloat {
        size * 0.46
    }

    var body: some View {
        Text(name.prefix(1).uppercased())
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(accent)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(accent.opacity(0.14))
            )
    }
}
