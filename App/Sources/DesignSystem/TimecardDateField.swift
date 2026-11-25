import SwiftUI

enum TimecardDateComponents { case date, time, dateAndTime }
private enum TimecardMomentPart: String, Identifiable {
    case date, time
    var id: Self { self }
}

/// Resolve local calendar edits before writing the caller's binding. Shift timestamps can
/// include seconds or be the second occurrence of a clock time when daylight saving ends.
enum TimecardMoment {
    static func moving(_ original: Date, toDay day: Date, calendar: Calendar, minimum: Date?, maximum: Date?) -> Date {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: original)
        let onDay: Date
        if calendar.isDate(original, inSameDayAs: day) {
            onDay = original
        } else {
            let start = calendar.startOfDay(for: day)
            // nextDate preserves minutes inside a spring-forward gap. bySettingHour
            // can round the requested local time down to the start of the first valid hour.
            onDay = calendar.nextDate(after: start.addingTimeInterval(-1), matching: parts,
                                      matchingPolicy: .nextTimePreservingSmallerComponents) ?? start
        }
        return min(max(onDay, minimum ?? .distantPast), maximum ?? .distantFuture)
    }

    static func time(hour: String, minute: String, twelveHour: Bool, afternoon: Bool,
                     on original: Date, calendar: Calendar, minimum: Date?, maximum: Date?) -> Date? {
        func number(_ text: String) -> Int? {
            let digits = text.compactMap(\.wholeNumberValue)
            guard (1...2).contains(text.count), digits.count == text.count, digits.allSatisfy({ (0...9).contains($0) }) else { return nil }
            return digits.reduce(0) { $0 * 10 + $1 }
        }
        guard let h = number(hour), let m = number(minute), (0..<60).contains(m),
              (twelveHour ? 1...12 : 0...23).contains(h) else { return nil }
        let clockHour = twelveHour ? h % 12 + (afternoon ? 12 : 0) : h
        let result: Date
        if calendar.component(.hour, from: original) == clockHour, calendar.component(.minute, from: original) == m {
            result = original
        } else {
            guard let value = calendar.date(bySettingHour: clockHour, minute: m, second: 0, of: original, matchingPolicy: .strict),
                  calendar.isDate(value, inSameDayAs: original) else { return nil }
            // Keep the same side of a repeated hour when editing a fall-back shift.
            if calendar.timeZone.secondsFromGMT(for: value) != calendar.timeZone.secondsFromGMT(for: original),
               let later = calendar.date(bySettingHour: clockHour, minute: m, second: 0, of: original,
                                         matchingPolicy: .strict, repeatedTimePolicy: .last),
               calendar.isDate(later, inSameDayAs: original),
               calendar.timeZone.secondsFromGMT(for: later) == calendar.timeZone.secondsFromGMT(for: original) {
                result = later
            } else { result = value }
        }
        return result >= (minimum ?? .distantPast) && result <= (maximum ?? .distantFuture) ? result : nil
    }
}

struct TimecardDateField: View {
    @Environment(\.calendar) private var environmentCalendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    @Binding var selection: Date
    let minimum: Date?
    let maximum: Date?
    let components: TimecardDateComponents
    let wholeHours: Bool
    @State private var editing: TimecardMomentPart?

    init(_ title: String, selection: Binding<Date>, minimum: Date? = nil, maximum: Date? = nil,
         components: TimecardDateComponents = .dateAndTime, wholeHours: Bool = false) {
        self.title = title
        _selection = selection
        self.minimum = minimum
        self.maximum = maximum
        self.components = components
        self.wholeHours = wholeHours
    }

    private var calendar: Calendar {
        var calendar = environmentCalendar
        calendar.timeZone = timeZone
        return calendar
    }

    var body: some View {
        Group {
            if components == .dateAndTime {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    Text(title)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    partButton(.date)
                    partButton(.time)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let part: TimecardMomentPart = components == .time ? .time : .date
                Button { editing = part } label: {
                    TimecardFieldLabel(title: title, value: value(part), symbol: part == .time ? "clock" : "calendar")
                }
                .accessibilityLabel(title).accessibilityValue(value(part))
            }
        }
        .buttonStyle(.plain)
        .sheet(item: $editing) { part in
            let caption = components == .dateAndTime ? title + (part == .date ? " date" : " time") : title
            let original = min(max(selection, minimum ?? .distantPast), maximum ?? .distantFuture)
            TimecardSheet(title: caption, preferredHeight: part == .date ? 490 : 550) {
                if part == .date {
                    TimecardCalendar(selection: Binding(get: { original }, set: { day in
                        selection = components == .dateAndTime
                            ? TimecardMoment.moving(original, toDay: day, calendar: calendar, minimum: minimum, maximum: maximum)
                            : day
                        editing = nil
                    }), minimum: minimum, maximum: maximum)
                } else {
                    TimecardClockEditor(original: original, minimum: minimum, maximum: maximum, wholeHours: wholeHours,
                                        calendar: calendar, locale: locale) {
                        selection = $0
                        editing = nil
                    }
                }
            }
        }
    }

    private func value(_ part: TimecardMomentPart) -> String {
        selection.formatted(Date.FormatStyle(date: part == .date ? .abbreviated : .omitted, time: part == .date ? .omitted : .shortened,
                                             locale: locale, calendar: calendar, timeZone: timeZone))
    }

    private func partButton(_ part: TimecardMomentPart) -> some View {
        Button { editing = part } label: {
            Text(value(part)).font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(TimecardColor.blueInk).padding(.horizontal, 8).frame(minHeight: 44)
                .overlay(alignment: .bottom) { Rectangle().fill(TimecardColor.rule).frame(height: 1) }
        }
        .accessibilityLabel(title + (part == .time ? " time" : " date")).accessibilityValue(value(part))
    }
}

private struct TimecardClockEditor: View {
    let original: Date
    let minimum: Date?
    let maximum: Date?
    let wholeHours: Bool
    let calendar: Calendar
    let twelveHour: Bool
    let am: String
    let pm: String
    let save: (Date) -> Void
    @State private var hour: String
    @State private var minute: String
    @State private var afternoon: Bool

    init(original: Date, minimum: Date?, maximum: Date?, wholeHours: Bool,
         calendar: Calendar, locale: Locale, save: @escaping (Date) -> Void) {
        self.original = original
        self.minimum = minimum
        self.maximum = maximum
        self.wholeHours = wholeHours
        self.calendar = calendar
        self.save = save
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("j")
        twelveHour = formatter.dateFormat.contains("a")
        am = formatter.amSymbol
        pm = formatter.pmSymbol
        let h = calendar.component(.hour, from: original)
        _hour = State(initialValue: String(twelveHour ? (h + 11) % 12 + 1 : h))
        _minute = State(initialValue: wholeHours ? "00" : String(format: "%02d", calendar.component(.minute, from: original)))
        _afternoon = State(initialValue: h >= 12)
    }

    private enum Field { case hour, minute }
    @State private var field: Field = .hour
    @State private var replaceDigits = true
    @FocusState private var acceptsKeys: Bool

    private var candidate: Date? {
        TimecardMoment.time(hour: hour, minute: minute, twelveHour: twelveHour, afternoon: afternoon,
                            on: original, calendar: calendar, minimum: minimum, maximum: maximum)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                fieldButton(.hour)
                Text(":").font(TypeStyle.title).padding(.bottom, 8).accessibilityHidden(true)
                fieldButton(.minute).disabled(wholeHours).opacity(wholeHours ? 0.55 : 1)
            }
            if twelveHour {
                TimecardSegments(title: "Time of day", selection: $afternoon, options: [false, true]) { $0 ? pm : am }
            }
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(1...3, id: \.self) { column in
                            digitKey(row * 3 + column)
                        }
                    }
                }
                GridRow {
                    TimecardColor.sheet.gridCellUnsizedAxes([.horizontal, .vertical]).accessibilityHidden(true)
                    digitKey(0)
                    Button { erase() } label: {
                        Image(systemName: "delete.left").frame(maxWidth: .infinity, minHeight: 48)
                            .background(TimecardColor.sheet).contentShape(Rectangle())
                    }.accessibilityLabel("Delete digit")
                }
            }
            .padding(1).background(TimecardColor.rule)
            .foregroundStyle(TimecardColor.ink)
            if candidate == nil, !hour.isEmpty, !minute.isEmpty {
                Text("Enter a valid time within the allowed range.").font(.footnote).foregroundStyle(TimecardColor.redInk)
            }
            Button("Use time") { if let candidate { save(candidate) } }
                .buttonStyle(AppActionButtonStyle()).disabled(candidate == nil)
        }
        .padding(.vertical, 12)
        .focusable().focusEffectDisabled().focused($acceptsKeys)
        .onAppear { acceptsKeys = true }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let digit = press.characters.first?.wholeNumberValue, (0...9).contains(digit) else { return .ignored }
            enter(digit)
            return .handled
        }
        .onKeyPress(.delete) { erase(); return .handled }
    }

    private func fieldButton(_ part: Field) -> some View {
        let selected = part == field
        let text = part == .hour ? hour : minute
        let title = part == .hour ? "Hour" : "Minute"
        return Button {
            field = part
            replaceDigits = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(TimecardType.label).foregroundStyle(TimecardColor.graphite)
                Text(text.isEmpty ? "—" : text)
                    .font(TypeStyle.title).monospacedDigit()
                    .foregroundStyle(selected ? TimecardColor.chalk : TimecardColor.ink)
                    .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .background(selected ? TimecardColor.cobalt : TimecardColor.inset)
            }.contentShape(Rectangle())
        }
        .accessibilityLabel(title).accessibilityValue(text)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func digitKey(_ digit: Int) -> some View {
        Button { enter(digit) } label: {
            Text(String(digit)).font(TypeStyle.title2).monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(TimecardColor.sheet).contentShape(Rectangle())
        }
    }

    private func enter(_ digit: Int) {
        let previous = field == .hour ? hour : minute
        let value = replaceDigits || previous.count == 2 ? String(digit) : previous + String(digit)
        replaceDigits = false
        if field == .hour {
            hour = value
            let maximumHour = twelveHour ? 12 : 23
            if !wholeHours, let h = Int(value), (twelveHour ? 1...12 : 0...23).contains(h),
               value.count == 2 || h * 10 > maximumHour {
                field = .minute
                replaceDigits = true
            }
        } else {
            minute = value
        }
    }

    private func erase() {
        if field == .hour { hour = String(hour.dropLast()) }
        else { minute = String(minute.dropLast()) }
        replaceDigits = false
    }
}
