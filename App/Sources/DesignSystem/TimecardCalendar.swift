import SwiftUI

struct TimecardCalendar: View {
    @Environment(\.calendar) private var environmentCalendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var selection: Date
    var minimum: Date? = nil
    var maximum: Date? = nil

    private enum Page { case days, months, years }
    @State private var page: Page = .days
    @State private var browsing: Date?

    private var calendar: Calendar {
        var calendar = environmentCalendar
        calendar.timeZone = timeZone
        return calendar
    }
    private var format: Date.FormatStyle { Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone) }
    private var anchor: Date { browsing ?? selection }
    private var month: DateInterval { calendar.dateInterval(of: .month, for: anchor)! }
    private var year: DateInterval { calendar.dateInterval(of: .year, for: anchor)! }
    private var firstYear: Date {
        let offset = calendar.component(.year, from: year.start) % 10
        return calendar.date(byAdding: .year, value: -offset, to: year.start) ?? year.start
    }
    private var displayTitle: String {
        switch page {
        case .days: anchor.formatted(format.month(.wide).year())
        case .months: anchor.formatted(format.year())
        case .years: firstYear.formatted(format.year()) + "–" + (calendar.date(byAdding: .year, value: 9, to: firstYear) ?? firstYear).formatted(format.year())
        }
    }

    private func available(_ interval: DateInterval) -> Bool {
        (minimum.map { interval.end > $0 } ?? true) && (maximum.map { interval.start <= $0 } ?? true)
    }

    private func adjacent(_ direction: Int) -> Date? {
        let next: Date?
        let interval: DateInterval?
        switch page {
        case .days:
            next = calendar.date(byAdding: .month, value: direction, to: month.start)
            interval = next.flatMap { calendar.dateInterval(of: .month, for: $0) }
        case .months:
            next = calendar.date(byAdding: .year, value: direction, to: year.start)
            interval = next.flatMap { calendar.dateInterval(of: .year, for: $0) }
        case .years:
            next = calendar.date(byAdding: .year, value: direction * 10, to: firstYear)
            interval = next.flatMap { start in calendar.date(byAdding: .year, value: 10, to: start).map { DateInterval(start: start, end: $0) } }
        }
        guard let interval, available(interval) else { return nil }
        return next
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Button {
                    switch page { case .days: page = .months; case .months: page = .years; case .years: page = .months }
                } label: {
                    HStack(spacing: 7) {
                        Text(displayTitle).font(TypeStyle.title2)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }.frame(minHeight: 44)
                }
                .accessibilityIdentifier("timecard.calendar.heading")
                .accessibilityHint(page == .days ? "Choose a month" : "Choose a year or month")
                Spacer(minLength: 0)
                navButton(-1)
                navButton(1)
            }
            .foregroundStyle(TimecardColor.blueInk)
            .overlay(alignment: .bottom) { Rectangle().fill(TimecardColor.rule).frame(height: 1) }

            switch page {
            case .days: dayGrid
            case .months:
                let count = calendar.range(of: .month, in: .year, for: anchor)?.count ?? 12
                periodGrid(start: year.start, count: count, unit: .month)
            case .years: periodGrid(start: firstYear, count: 10, unit: .year)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: selection) { _, newDate in browsing = newDate }
    }

    private func navButton(_ direction: Int) -> some View {
        let target = adjacent(direction)
        let unit = page == .days ? "month" : (page == .months ? "year" : "ten years")
        return Button {
            if let target { browsing = target }
        } label: {
            Image(systemName: direction < 0 ? "chevron.backward" : "chevron.forward")
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .disabled(target == nil).opacity(target == nil ? 0.35 : 1)
        .accessibilityLabel((direction < 0 ? "Previous " : "Next ") + unit)
    }

    private var dayGrid: some View {
        let large = typeSize.isAccessibilitySize
        let count = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 0
        let weekLength = calendar.weekdaySymbols.count
        let lead = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + weekLength) % weekLength
        let columns = large ? 3 : weekLength
        let blanks = large ? 0 : lead
        let rows = (blanks + count + columns - 1) / columns
        return VStack(spacing: 2) {
            if !large {
                HStack(spacing: 0) {
                    ForEach(0..<weekLength, id: \.self) { index in
                        let day = calendar.date(byAdding: .day, value: index - lead, to: month.start) ?? month.start
                        Text(day.formatted(format.weekday(.abbreviated))).textCase(.uppercase)
                            .font(TimecardType.label).foregroundStyle(TimecardColor.graphite)
                            .frame(maxWidth: .infinity).accessibilityHidden(true)
                    }
                }
            }
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column - blanks
                        if (0..<count).contains(index), let day = calendar.date(byAdding: .day, value: index, to: month.start),
                           let interval = calendar.dateInterval(of: .day, for: day) {
                            dayButton(day, enabled: available(interval))
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 1).accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    private func dayButton(_ day: Date, enabled: Bool) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: selection)
        return Button { selection = max(day, minimum ?? day) } label: {
            VStack(spacing: 1) {
                if typeSize.isAccessibilitySize { Text(day.formatted(format.weekday(.abbreviated))).font(.caption) }
                Text(day.formatted(format.day())).font(TimecardType.display(23, relativeTo: .body))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(selected ? TimecardColor.chalk : TimecardColor.ink)
            .background(selected ? TimecardColor.cobalt : .clear)
            .overlay(alignment: .bottom) {
                if calendar.isDateInToday(day) { Rectangle().fill(selected ? TimecardColor.chalk : TimecardColor.redInk).frame(width: 14, height: 2) }
            }
            .contentShape(Rectangle())
        }
        .disabled(!enabled).opacity(enabled || selected ? 1 : 0.3)
        .accessibilityLabel(day.formatted(format.weekday(.wide).month(.wide).day().year()))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func periodGrid(start: Date, count: Int, unit: Calendar.Component) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 2 : 3), spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                if let date = calendar.date(byAdding: unit, value: index, to: start),
                   let interval = calendar.dateInterval(of: unit, for: date) {
                    let current = calendar.isDate(date, equalTo: selection, toGranularity: unit)
                    let enabled = available(interval)
                    Button {
                        browsing = date
                        page = unit == .year ? .months : .days
                    } label: {
                        Text(date.formatted(unit == .year ? format.year() : format.month(.abbreviated)))
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(current ? TimecardColor.chalk : TimecardColor.ink)
                            .background(current ? TimecardColor.cobalt : TimecardColor.inset)
                    }
                    .disabled(!enabled).opacity(enabled ? 1 : 0.3)
                    .accessibilityAddTraits(current ? .isSelected : [])
                }
            }
        }
    }
}
