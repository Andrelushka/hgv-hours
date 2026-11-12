import SwiftUI
import SwiftData
import MapKit

/// Overspeed events between two times (a day or a shift). Over 60 s = infringement.
struct SpeedEventsSection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SpeedEvent.start) private var events: [SpeedEvent]
    var from: Date
    var to: Date

    var body: some View {
        let list = events.filter { $0.start >= from && $0.start < to }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                let infringements = list.filter(\.isInfringement).count
                Label("Overspeed: \(list.count) event\(list.count == 1 ? "" : "s")\(infringements > 0 ? " · \(infringements) infringement\(infringements == 1 ? "" : "s")" : "")",
                      systemImage: "gauge.with.dots.needle.100percent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(infringements > 0 ? .red : .orange)
                ForEach(list.reversed()) { e in
                    HStack {
                        Image(systemName: e.isInfringement ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(e.isInfringement ? .red : .orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Fmt.time(e.start)) · \(Int(e.maxKmh.rounded())) km/h max (limit \(Int(e.limitKmh)))")
                                .font(.caption.weight(.semibold))
                            Text("\(Int(e.duration)) s\(e.isInfringement ? " — infringement (over 60 s)" : " — recorded, not an infringement")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if e.hasLocation {
                            Button {
                                let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: e.latitude, longitude: e.longitude)))
                                item.name = "Overspeed \(Fmt.time(e.start))"
                                item.openInMaps()
                            } label: { Image(systemName: "map") }
                            .buttonStyle(.borderless)
                        }
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            context.delete(e)
                            try? context.save()
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
