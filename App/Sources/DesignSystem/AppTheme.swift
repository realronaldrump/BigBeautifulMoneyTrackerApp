import Observation
import SwiftUI

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
    let tertiaryText = Color.white.opacity(0.48)

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

    var metallicGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.95),
                takeHomeAccent.opacity(0.82),
                roseAccent.opacity(0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
            colors: [accent.opacity(0.52), complementaryAccent(for: mode).opacity(0.16), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct BrandHeader: View {
    @Environment(AppTheme.self) private var theme

    let eyebrow: String
    let subtitle: String
    let mode: EarningsDisplayMode
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            HStack(spacing: 10) {
                BrandSeal(mode: mode)

                Text(eyebrow.uppercased())
                    .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(theme.takeHomeAccent.opacity(0.92))
            }

            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                Text(AppTheme.brandName)
                    .font(.system(size: compact ? 24 : 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: compact ? 15 : 17, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 18 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 28 : 34, style: .continuous)
                .fill(theme.panelFill(for: mode))
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 28 : 34, style: .continuous)
                        .strokeBorder(theme.brandStroke, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(theme.glow(for: mode))
                        .frame(width: compact ? 96 : 130, height: compact ? 96 : 130)
                        .blur(radius: compact ? 24 : 32)
                        .offset(x: compact ? 10 : 18, y: compact ? -16 : -22)
                }
        )
        .shadow(color: theme.accent(for: mode).opacity(compact ? 0.14 : 0.20), radius: compact ? 18 : 28, y: 12)
    }
}

private struct BrandSeal: View {
    @Environment(AppTheme.self) private var theme

    let mode: EarningsDisplayMode

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.metallicGradient)
                .frame(width: 34, height: 34)

            Circle()
                .fill(theme.trueBlack)
                .frame(width: 26, height: 26)

            Image(systemName: mode == .gross ? "dollarsign.circle.fill" : "chart.line.uptrend.xyaxis.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.accent(for: mode))
        }
    }
}
