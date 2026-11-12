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
            NowPill {
                // Whole minute, like the picker shows.
                let now = Calendar.current.date(bySetting: .second, value: 0, of: .now) ?? .now
                selection = clamp(min(now, .now))
            }
        }
    }
}


/// Small "Now" capsule that sets a time to now.
struct NowPill: View {
    var action: () -> Void

    var body: some View {
        // A plain tappable text, not a Button: a picker with hidden labels hides a button's text.
        Text("Now")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .fixedSize()
            .accessibilityAddTraits(.isButton)
    }
}
