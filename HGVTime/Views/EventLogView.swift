import SwiftUI
import SwiftData

/// Every logged event with time, place and details. Filter by type; export as CSV.
struct EventLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EventLog.time, order: .reverse) private var events: [EventLog]
    /// nil = all days.
    var day: Date?
    /// Only these kinds (nil = all).
    var kinds: Set<EventKind>? = nil
    @State private var filter: EventKind?
    @State private var selected: EventLog?

    var body: some View {
        let cal = Calendar.hgv
        let list = events.filter { e in
            (day.map { cal.isDate(e.time, inSameDayAs: $0) } ?? true) && (filter == nil || e.kind == filter)
                && (kinds.map { $0.contains(e.kind) } ?? true)
        }
        let byDay = Dictionary(grouping: list) { cal.startOfDay(for: $0.time) }
        List {
            if list.isEmpty {
                ContentUnavailableView("No events", systemImage: "list.bullet.rectangle",
                                       description: Text("Shift starts and ends, activity changes, card in/out, stops, fuel, overspeed and infringements are logged here with where they happened."))
            }
            ForEach(byDay.keys.sorted(by: >), id: \.self) { d in
                Section {
                    ForEach((byDay[d] ?? []).sorted { $0.time > $1.time }) { e in
                        Button { selected = e } label: {
                            HStack(spacing: 10) {
                                EventPin(event: e)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.title).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(e.kind.isProblem ? .red : .primary)
                                    if !e.detail.isEmpty { Text(e.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(Fmt.time(e.time)).font(.caption.monospacedDigit())
                                    if e.hasLocation { Image(systemName: "mappin").font(.caption2).foregroundStyle(.secondary) }
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            // Change records are kept so the driver log stays trustworthy.
                            if e.kind != .correction {
                                Button("Delete", systemImage: "trash", role: .destructive) { context.delete(e); try? context.save() }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(d.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        Spacer()
                        NavigationLink { MapScreen(day: d) } label: { Label("Map", systemImage: "map").labelStyle(.titleAndIcon) }
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle(kinds == [.correction] ? "Changes" : (day == nil ? "Event log" : "Events \(Fmt.day(day!))"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Show", selection: $filter) {
                        Text("All events").tag(EventKind?.none)
                        ForEach(EventKind.allCases) { Label($0.title, systemImage: $0.symbol).tag(EventKind?.some($0)) }
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: csv(list)) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .sheet(item: $selected) { EventDetailSheet(event: $0).presentationDetents([.fraction(0.3), .medium]) }
    }

    private func csv(_ list: [EventLog]) -> URL {
        var lines = ["Date,Time,Event,Details,Latitude,Longitude,Speed km/h,Duration s"]
        for e in list.reversed() {
            let fields = [Fmt.isoDate(e.time), Fmt.time(e.time), e.title, e.detail,
                          e.hasLocation ? String(format: "%.5f", e.latitude) : "", e.hasLocation ? String(format: "%.5f", e.longitude) : "",
                          e.speedKmh > 0 ? String(Int(e.speedKmh)) : "", e.duration > 0 ? String(Int(e.duration)) : ""]
            lines.append(fields.map { $0.contains(",") ? "\"\($0)\"" : $0 }.joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HGV-events.csv")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
