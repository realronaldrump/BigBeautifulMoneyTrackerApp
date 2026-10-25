import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WrappingHStack: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat?) -> (size: CGSize, frames: [CGRect]) {
        let available = max(1, width ?? 10_000)
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: available, height: nil))
            if x > 0 && x + size.width > available {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: width ?? usedWidth, height: frames.isEmpty ? 0 : y + rowHeight), frames)
    }
}

struct AdaptiveCardGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var minimumWidth: CGFloat = 144
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.adaptive(minimum: minimumWidth), spacing: spacing)],
            spacing: spacing
        ) { content }
    }
}

struct AppValueRow: View {
    @Environment(AppTheme.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String
    var accent: Color = .white

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        titleText.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 12)
                        valueText.fixedSize(horizontal: true, vertical: false)
                    }
                    stacked
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 5) { titleText; valueText }
    }

    private var titleText: some View {
        Text(title).font(TypeStyle.callout).foregroundStyle(theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value).font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(accent).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.35)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct AppActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 18)
            .padding(.vertical, 5)
            .background(accent.opacity(isEnabled ? 1 : 0.36), in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct AppInlineNotice: View {
    let message: String
    var systemImage = "exclamationmark.circle.fill"
    var color: Color = Color(red: 1, green: 0.63, blue: 0.68)

    var body: some View {
        Label {
            Text(message).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).accessibilityHidden(true)
        }
        .font(TypeStyle.callout)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct ShiftDurationSummary: View {
    let startDate: Date
    let endDate: Date

    var body: some View {
        if endDate > startDate {
            AppValueRow(title: "Duration", value: (endDate.timeIntervalSince(startDate) / 3600)
                .formatted(.number.precision(.fractionLength(0...2))) + " hours")
            if !Calendar.current.isDate(startDate, inSameDayAs: endDate) {
                Label("Ends \(endDate.formatted(date: .abbreviated, time: .shortened))", systemImage: "moon.stars")
                    .font(TypeStyle.caption).foregroundStyle(.secondary)
            }
        } else {
            AppInlineNotice(message: "Choose an end time after the start.")
        }
    }
}

private struct AppKeyboardToolbar: ViewModifier {
    func body(content: Content) -> some View {
        #if canImport(UIKit)
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .accessibilityLabel("Dismiss keyboard")
                }
            }
        #else
        content
        #endif
    }
}

extension View {
    func appKeyboardToolbar() -> some View { modifier(AppKeyboardToolbar()) }
}
