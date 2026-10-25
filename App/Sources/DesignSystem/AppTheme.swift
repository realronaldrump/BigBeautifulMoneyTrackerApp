import Observation
import SwiftUI

// MARK: - Design Tokens

enum CornerRadius {
    static let cardLarge: CGFloat = 24
    static let cardSmall: CGFloat = 16
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
}

enum TypeStyle {
    static let headline: Font = .system(.largeTitle, design: .rounded, weight: .bold)
    static let title: Font = .system(.title2, design: .rounded, weight: .bold)
    static let title2: Font = .system(.title3, design: .rounded, weight: .semibold)
    static let title3: Font = .system(.headline, design: .rounded, weight: .semibold)
    static let body: Font = .system(.body, design: .rounded, weight: .medium)
    static let callout: Font = .system(.callout, design: .rounded, weight: .medium)
    static let caption: Font = .system(.footnote, design: .rounded, weight: .medium)
    static let micro: Font = .system(.caption2, design: .rounded, weight: .semibold)
}

// MARK: - Theme

@MainActor
@Observable
final class AppTheme {
    static let brandName = "Davis's Big Beautiful Money Tracker App"

    let trueBlack = Color(red: 0.03, green: 0.04, blue: 0.05)
    let panel = Color(red: 0.08, green: 0.09, blue: 0.11)
    let secondaryPanel = Color(red: 0.12, green: 0.13, blue: 0.15)
    let grossAccent = Color(red: 0.30, green: 0.94, blue: 0.62)
    let takeHomeAccent = Color(red: 0.95, green: 0.78, blue: 0.38)
    let roseAccent = Color(red: 0.90, green: 0.48, blue: 0.60)
    let secondaryText = Color.white.opacity(0.72)
    let tertiaryText = Color.white.opacity(0.62)

    func accent(for mode: EarningsDisplayMode) -> Color {
        switch mode {
        case .gross:
            grossAccent
        case .takeHome:
            takeHomeAccent
        }
    }

    func complementaryAccent(for mode: EarningsDisplayMode) -> Color {
        switch mode {
        case .gross:
            takeHomeAccent
        case .takeHome:
            grossAccent
        }
    }

    var brandStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.28),
                takeHomeAccent.opacity(0.30),
                grossAccent.opacity(0.32)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func panelFill(for mode: EarningsDisplayMode) -> LinearGradient {
        LinearGradient(
            colors: [
                panel.opacity(0.98),
                secondaryPanel.opacity(0.98),
                accent(for: mode).opacity(0.12),
                complementaryAccent(for: mode).opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func glow(for mode: EarningsDisplayMode) -> LinearGradient {
        let accent = accent(for: mode)
        return LinearGradient(
            colors: [accent.opacity(0.18), complementaryAccent(for: mode).opacity(0.06), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Glass Card Modifier

struct GlassCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat
    let accent: Color
    let hasShadow: Bool

    init(
        cornerRadius: CGFloat = CornerRadius.cardLarge,
        accent: Color = .white,
        hasShadow: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.accent = accent
        self.hasShadow = hasShadow
    }

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base translucent fill
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(reduceTransparency ? AnyShapeStyle(Color(red: 0.08, green: 0.09, blue: 0.11)) : AnyShapeStyle(.ultraThinMaterial))
                        .environment(\.colorScheme, .dark)

                    // Tinted overlay so cards stay rich on pure-dark backgrounds
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(red: 0.08, green: 0.09, blue: 0.11).opacity(0.55))

                    // Inner light edge (top-left highlight)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.06),
                                    accent.opacity(0.08),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(
                color: hasShadow ? accent.opacity(0.10) : .clear,
                radius: hasShadow ? 20 : 0,
                y: hasShadow ? 8 : 0
            )
    }
}

extension View {
    func glassCard(
        cornerRadius: CGFloat = CornerRadius.cardLarge,
        accent: Color = .white,
        hasShadow: Bool = true
    ) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, accent: accent, hasShadow: hasShadow))
    }
}

struct BrandHeader: View {
    @Environment(AppTheme.self) private var theme

    let eyebrow: String
    let subtitle: String
    let mode: EarningsDisplayMode
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            HStack(spacing: 10) {
                BrandSeal(mode: mode)
                Text(AppTheme.brandName)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(.system(compact ? .title2 : .largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(TypeStyle.callout)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 18 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: CornerRadius.cardLarge, accent: theme.accent(for: mode), hasShadow: false)
    }
}

private struct BrandSeal: View {
    @Environment(AppTheme.self) private var theme

    let mode: EarningsDisplayMode

    var body: some View {
        Image("BrandLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.brandStroke, lineWidth: 1)
            }
            .shadow(color: theme.accent(for: mode).opacity(0.18), radius: 10, y: 4)
            .accessibilityHidden(true)
    }
}
