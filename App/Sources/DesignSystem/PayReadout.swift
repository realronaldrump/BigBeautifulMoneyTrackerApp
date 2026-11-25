import SwiftUI

/// The clipped corner is the orientation mark found on physical time cards.
private struct TimecardCut: Shape {
    func path(in rect: CGRect) -> Path {
        let cut = min(19, min(rect.width, rect.height) / 4)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct PayReadout<Detail: View>: View {
    let title: String
    let amount: Double
    let mode: EarningsDisplayMode
    @ViewBuilder var detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).textCase(.uppercase).tracking(0.9).font(TimecardType.label)
                .fixedSize(horizontal: false, vertical: true)
            RollingCurrencyText(amount: amount)
            detail
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.horizontal, 18).padding(.vertical, 17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(mode == .gross ? TimecardColor.chalk : TimecardColor.ink)
        .background(mode == .gross ? TimecardColor.cobalt : TimecardColor.inset, in: TimecardCut())
    }
}

struct TimecardHeading: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var detail: String? = nil

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(title).font(TypeStyle.headline).foregroundStyle(TimecardColor.ink)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if let detail {
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(detail).font(TimecardType.label).foregroundStyle(TimecardColor.graphite)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(TimecardColor.ink).frame(height: 2) }
    }
}

extension View {
    func timecardForm() -> some View {
        scrollContentBackground(.hidden)
            .background(TimecardColor.stock.ignoresSafeArea())
            .tint(TimecardColor.blueInk)
    }

    func ruledSection() -> some View {
        overlay(alignment: .bottom) { Rectangle().fill(TimecardColor.rule).frame(height: 1) }
    }
}
