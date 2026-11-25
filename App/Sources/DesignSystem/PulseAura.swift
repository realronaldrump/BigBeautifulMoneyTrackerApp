import SwiftUI

struct PulseAura: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let accent: Color

    var body: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.title2)
            .foregroundStyle(accent)
            .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            .accessibilityHidden(true)
    }
}
