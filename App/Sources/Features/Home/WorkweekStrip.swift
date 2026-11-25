import SwiftUI

/// Each punch represents completed work on that calendar day, including the
/// correct portion of a shift crossing midnight or a daylight-saving boundary.
struct WorkweekStrip: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let shifts: [ShiftRecord]
    let asOf: Date

    private struct Day: Identifiable {
        let id: Date
        let hours: Double
        var spokenDate: String { id.formatted(date: .complete, time: .omitted) }
        var spokenHours: String { hours.formatted(.number.precision(.fractionLength(0...2))) + " hours worked" }

        var hoursText: String {
            hours.formatted(.number.precision(.fractionLength(0...1))) + "h"
        }
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: asOf)
        guard let first = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }
        let relevant = AggregationService.filtered(shifts, in: DateInterval(start: first, end: asOf))
        return (0..<7).compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: offset, to: first),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return Day(id: start, hours: AggregationService.totalHours(for: relevant, in: DateInterval(start: start, end: min(end, asOf))))
        }
    }

    var body: some View {
        let week = days
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 days").font(TypeStyle.title2).accessibilityAddTraits(.isHeader)
            if typeSize.isAccessibilitySize {
                ForEach(week) { day in
                    HStack {
                        punch(day)
                        Text(day.id.formatted(.dateTime.weekday(.abbreviated).day()))
                        Spacer()
                        Text(day.hoursText).monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.spokenDate)
                    .accessibilityValue(day.spokenHours)
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(week) { day in
                        VStack(spacing: 5) {
                            Text(day.id.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                .font(.system(.caption2, design: .monospaced))
                            Text(day.id.formatted(.dateTime.day()))
                                .font(TimecardType.display(24, relativeTo: .title3))
                            punch(day)
                            Text(day.hours > 0 ? day.hoursText : "—")
                                .font(.system(.caption, design: .monospaced))
                        }
                        .foregroundStyle(Calendar.current.isDate(day.id, inSameDayAs: asOf) ? TimecardColor.redInk : TimecardColor.ink)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .leading) {
                            if day.id != week.first?.id { Rectangle().fill(TimecardColor.rule).frame(width: 1) }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(day.spokenDate)
                        .accessibilityValue(day.spokenHours)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .ruledSection()
    }

    private func punch(_ day: Day) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(day.hours > 0 ? TimecardColor.blueInk : .clear)
            .frame(width: 15, height: 6)
            .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(day.hours > 0 ? TimecardColor.blueInk : TimecardColor.rule) }
            .accessibilityHidden(true)
    }
}
