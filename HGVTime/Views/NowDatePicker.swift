import SwiftUI

/// A date/time picker with a "Now" button next to it.
struct NowDatePicker: View {
    private let title: LocalizedStringKey
    @Binding private var selection: Date
    private let picker: AnyView
    private let clamp: (Date) -> Date

    init(_ title: LocalizedStringKey, selection: Binding<Date>,
         displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.title = title
        _selection = selection
        picker = AnyView(DatePicker(title, selection: selection, displayedComponents: displayedComponents))
        clamp = { $0 }
    }

    init(_ title: LocalizedStringKey, selection: Binding<Date>, in range: ClosedRange<Date>,
         displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.title = title
        _selection = selection
        picker = AnyView(DatePicker(title, selection: selection, in: range, displayedComponents: displayedComponents))
        clamp = { min(max($0, range.lowerBound), range.upperBound) }
    }

    init(_ title: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeFrom<Date>,
         displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.title = title
        _selection = selection
        picker = AnyView(DatePicker(title, selection: selection, in: range, displayedComponents: displayedComponents))
        clamp = { max($0, range.lowerBound) }
    }

    init(_ title: LocalizedStringKey, selection: Binding<Date>, in range: PartialRangeThrough<Date>,
         displayedComponents: DatePickerComponents = [.date, .hourAndMinute]) {
        self.title = title
        _selection = selection
        picker = AnyView(DatePicker(title, selection: selection, in: range, displayedComponents: displayedComponents))
        clamp = { min($0, range.upperBound) }
    }

    var body: some View {
        HStack(spacing: 8) {
            picker
            Button("Now") {
                // Whole minute, like the picker shows.
                let now = Calendar.current.date(bySetting: .second, value: 0, of: .now) ?? .now
                selection = clamp(min(now, .now))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption.weight(.semibold))
            .accessibilityLabel("Set \(Text(title)) to now")
        }
    }
}
