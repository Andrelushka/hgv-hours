import MapKit
import SwiftData
import SwiftUI

/// Full-screen turn-by-turn navigation.
struct NavigationModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var store
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @State private var engine = NavigationEngine()
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    var target: MapScreen.NavTarget

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                UserAnnotation()
                if let route = engine.route {
                    MapPolyline(route.polyline).stroke(.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
                if let d = engine.destination {
                    Marker(engine.destinationName, systemImage: "flag.checkered", coordinate: d).tint(.indigo)
                }
                ForEach(engine.parkingOptions, id: \.self) { item in
                    Marker(item.name ?? "Parking", systemImage: "parkingsign.circle.fill", coordinate: item.placemark.coordinate).tint(.green)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .including([.parking, .gasStation]), showsTraffic: true))
            .mapControls { MapCompass(); MapScaleView() }
            .ignoresSafeArea()

            VStack(spacing: 8) {
                instructionBanner
                Spacer()
                bottomPanel
            }
            .padding()
        }
        .onAppear {
            engine.driveLeft = { driveLeftNow() }
            if let c = target.coordinate {
                engine.start(to: c, name: target.name)
            } else {
                Task {
                    let placemark = try? await CLGeocoder().geocodeAddressString(target.address).first
                    if let c = placemark?.location?.coordinate { engine.start(to: c, name: target.name) } else { engine.status = "Couldn't find that address." }
                }
            }
        }
        .onDisappear { engine.stop() }
    }

    private var instructionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").font(.largeTitle).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                if let d = engine.distanceToNextManeuver {
                    Text(NavigationEngine.distanceText(d)).font(.title2.weight(.bold)).foregroundStyle(.white)
                }
                let next = engine.route.flatMap { r in engine.stepIndex + 1 < r.steps.count ? r.steps[engine.stepIndex + 1].instructions : nil }
                Text(next ?? engine.currentStep?.instructions ?? engine.status)
                    .font(.headline).foregroundStyle(.white).lineLimit(2)
            }
            Spacer()
        }
        .padding()
        .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 18))
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(engine.eta.map { "Arrive \(Fmt.time($0))" } ?? "—").font(.title3.weight(.bold).monospacedDigit())
                    Text("\(NavigationEngine.distanceText(engine.remainingDistance)) · \(engine.destinationName)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) { engine.stop(); dismiss() } label: {
                    Text("End").font(.headline).padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            if let h = heightText {
                Label(h, systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            if engine.notEnoughTime {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Not enough driving time to arrive", systemImage: "clock.badge.exclamationmark")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.red)
                    Text("Places to stop within reach (check they suit your vehicle):").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(engine.parkingOptions, id: \.self) { item in
                                Button {
                                    engine.start(to: item.placemark.coordinate, name: item.name ?? "Parking")
                                } label: {
                                    Label(item.name ?? "Parking", systemImage: "parkingsign.circle.fill").font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var heightText: String? {
        let ids = [store.settings.currentVehicleID, store.settings.currentTrailerID]
        let h = vehicles.filter { ids.contains($0.id.uuidString) }.map(\.height).max() ?? 0
        return h > 0 ? "Your height: \(Fmt.length(h, feet: true)). Route isn't checked for low bridges — follow the signs." : nil
    }

    private func driveLeftNow() -> TimeInterval {
        let settings = store.settings
        let snaps = ActivityController.recentSnapshots(context: context, settings: settings)
        let s = RulesEngine.status(snaps, now: .now, config: settings.ruleConfig)
        if let world = WorldRulesCache.refresh(snaps, now: .now, settings: settings) { return world.driveLeft }
        return s.currentShift == nil ? .infinity : s.driveAvailableNow
    }
}
