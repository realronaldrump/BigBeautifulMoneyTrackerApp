import SwiftUI

/// Slips share a heading and a close button. Scrolling keeps every choice reachable at large text sizes.
struct TimecardSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var tall = false
    var preferredHeight: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(title).font(TypeStyle.title).foregroundStyle(TimecardColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .foregroundStyle(TimecardColor.graphite).accessibilityLabel("Close")
            }
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(TimecardColor.ink).frame(height: 2) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }.scrollDismissesKeyboard(.interactively)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.top, 12)
        .presentationBackground(TimecardColor.stock)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(10)
        .presentationDetents(typeSize.isAccessibilitySize || tall ? [.large] : [preferredHeight.map { .height($0) } ?? .medium, .large])
    }
}

struct TimecardToolbarLabel: View {
    let symbol: String
    var title: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let title { Text(title).font(.subheadline.weight(.semibold)) }
            Image(systemName: symbol).font(title == nil ? .headline : .caption.weight(.bold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(TimecardColor.blueInk)
        .padding(.horizontal, 6).frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct TimecardFieldLabel: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let value: String
    var symbol = "chevron.up.chevron.down"

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(title).foregroundStyle(TimecardColor.ink)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
            HStack(spacing: 7) {
                Text(value).font(.subheadline.weight(.semibold))
                Image(systemName: symbol).font(.caption.weight(.bold)).accessibilityHidden(true)
            }.foregroundStyle(TimecardColor.blueInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct TimecardAction: Identifiable {
    let id: AnyHashable
    let title: String
    let symbol: String?
    let swatch: Color?
    let section: String?
    let selected: Bool?
    let destructive: Bool
    let perform: () -> Void

    init(_ title: String, id: AnyHashable? = nil, symbol: String? = nil, swatch: Color? = nil, section: String? = nil,
         selected: Bool? = nil, destructive: Bool = false, perform: @escaping () -> Void) {
        self.id = id ?? AnyHashable(title)
        self.title = title
        self.symbol = symbol
        self.swatch = swatch
        self.section = section
        self.selected = selected
        self.destructive = destructive
        self.perform = perform
    }
}

private struct TimecardActionList: View {
    let items: [TimecardAction]
    let choose: (TimecardAction) -> Void

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if let section = item.section, index == 0 || items[index - 1].section != section {
                Text(section).font(TimecardType.label).foregroundStyle(TimecardColor.graphite)
                    .textCase(.uppercase).padding(.top, 16).accessibilityAddTraits(.isHeader)
            }
            Button { choose(item) } label: {
                HStack(spacing: 12) {
                    if let swatch = item.swatch {
                        Rectangle().fill(swatch).frame(width: 14, height: 14).accessibilityHidden(true)
                    }
                    if let symbol = item.symbol { Image(systemName: symbol).frame(width: 22).accessibilityHidden(true) }
                    Text(item.title).font(.body.weight(item.selected == true ? .bold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let selected = item.selected {
                        ZStack {
                            Rectangle().strokeBorder(TimecardColor.rule, lineWidth: 1)
                            if selected {
                                Rectangle().fill(TimecardColor.cobalt)
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(TimecardColor.chalk)
                            }
                        }.frame(width: 21, height: 21).accessibilityHidden(true)
                    }
                }
                .foregroundStyle(item.destructive ? TimecardColor.redInk : TimecardColor.ink)
                .padding(.vertical, 8).frame(minHeight: 52).contentShape(Rectangle())
            }
            .accessibilityLabel(item.title)
            .accessibilityAddTraits(item.selected == true ? .isSelected : [])
            .ruledSection()
        }
    }
}

private struct TimecardActions: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let items: [TimecardAction]
    @State private var pending: TimecardAction?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            let action = pending
            pending = nil
            action?.perform()
        }) {
            let sections = Set(items.compactMap(\.section)).count
            let height = CGFloat(82 + 52 * items.count + 36 * sections)
            TimecardSheet(title: title, tall: items.count > 8, preferredHeight: height) {
                TimecardActionList(items: items) { item in
                    pending = item
                    isPresented = false
                }
            }
        }
    }
}

extension View {
    func timecardActions(_ title: String, isPresented: Binding<Bool>, items: [TimecardAction]) -> some View {
        modifier(TimecardActions(isPresented: isPresented, title: title, items: items))
    }
}

struct TimecardMenu<Label: View>: View {
    let title: String
    let items: [TimecardAction]
    @ViewBuilder var label: Label
    @State private var open = false

    var body: some View {
        Button { open = true } label: { label }.buttonStyle(.plain).disabled(items.isEmpty)
            .timecardActions(title, isPresented: $open, items: items)
    }
}

struct TimecardPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let name: (Value) -> String

    let swatch: ((Value) -> Color?)?

    init(_ title: String, selection: Binding<Value>, options: [Value], swatch: ((Value) -> Color?)? = nil,
         name: @escaping (Value) -> String) {
        self.swatch = swatch
        self.title = title
        _selection = selection
        self.options = options
        self.name = name
    }

    var body: some View {
        TimecardMenu(title: title, items: options.map { value in
            TimecardAction(name(value), id: AnyHashable(value), swatch: swatch?(value), selected: value == selection) { selection = value }
        }) {
            TimecardFieldLabel(title: title, value: name(selection))
        }
        .accessibilityLabel(title).accessibilityValue(name(selection))
    }
}

/// Direct selection for short, mutually exclusive choices such as pay type or AM/PM.
struct TimecardSegments<Value: Hashable>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let name: (Value) -> String

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 1)) : AnyLayout(HStackLayout(spacing: 1))
        layout {
            ForEach(options, id: \.self) { option in
                let selected = selection == option
                Button { selection = option } label: {
                    Text(name(option)).font(.headline)
                        .padding(.horizontal, 5).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected ? TimecardColor.chalk : TimecardColor.ink)
                        .background(selected ? TimecardColor.cobalt : TimecardColor.sheet)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(1).background(TimecardColor.rule)
        .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

struct TimecardDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    configuration.label
                    Spacer(minLength: 4)
                    Image(systemName: configuration.isExpanded ? "minus" : "plus")
                        .font(.caption.weight(.bold)).foregroundStyle(TimecardColor.blueInk)
                        .frame(width: 23, height: 23)
                        .overlay { Rectangle().strokeBorder(TimecardColor.rule) }
                        .accessibilityHidden(true)
                }
                .foregroundStyle(TimecardColor.ink)
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded {
                VStack(alignment: .leading, spacing: 10) { configuration.content }
                    .padding(.leading, 12).padding(.vertical, 5)
                    .overlay(alignment: .leading) { Rectangle().fill(TimecardColor.rule).frame(width: 1) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TimecardJobPicker: View {
    let jobs: [JobProfile]
    @Binding var selection: UUID?

    var body: some View {
        TimecardPicker("Job", selection: $selection, options: jobs.map { Optional($0.id) }) { id in
            jobs.first { $0.id == id }?.displayName ?? "Choose job"
        }
    }
}
