import MapKit
import SwiftUI

/// Today tiles shown while navigating: small map, next turn, road, speed limit, arrival, voice.
struct NavTile: View {
    @Environment(SettingsStore.self) private var store
    @State private var nav = NavigationEngine.shared
    @State private var opening = false
    var tile: Tile

    var body: some View {
        Button { if tile != .navVoice { opening = true } else { toggleVoice() } } label: { content }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $opening) { NavigationModeView(target: nil) }
    }

    @ViewBuilder
    private var content: some View {
        switch tile {
        case .navMap:
            ZStack(alignment: .bottomLeading) {
                Map(initialPosition: .userLocation(followsHeading: true, fallback: .automatic), interactionModes: []) {
                    if let route = nav.route { MapPolyline(route.polyline).stroke(.blue, lineWidth: 5) }
                    if let c = nav.displayCoordinate ?? nav.location?.coordinate {
                        Annotation("", coordinate: c) { TruckMarker(rotation: nav.heading).environment(store).scaleEffect(0.7) }
                    }
                    if let d = nav.destination { Marker(nav.destinationName, systemImage: "flag.checkered", coordinate: d).tint(.indigo) }
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                Label("Open navigation", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold)).padding(6).background(.regularMaterial, in: Capsule()).padding(8)
            }
        case .navTurn:
            HStack(spacing: 12) {
                Image(systemName: nav.nextStep?.symbol ?? "flag.checkered").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 54, height: 54).background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(nav.distanceToNextManeuver.map(NavigationEngine.distanceText) ?? "—").font(.title2.weight(.bold)).monospacedDigit()
                    Text(nav.nextInstruction.isEmpty ? nav.status : nav.nextInstruction).font(.subheadline).lineLimit(2)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        case .navRoad:
            small("Road", value: nav.roadRef ?? (nav.currentRoad.isEmpty ? "—" : nav.currentRoad), symbol: "road.lanes")
        case .navSpeedLimit:
            VStack(spacing: 4) {
                Text("Speed limit").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(nav.speedLimitText ?? "–")
                    .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                    .frame(width: 54, height: 54).background(Circle().fill(.white)).overlay(Circle().stroke(.red, lineWidth: 6))
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        case .navArrival:
            small("Arrive \(nav.eta.map(Fmt.time) ?? "—")",
                  value: "\(Fmt.hm(nav.remainingTime)) · \(NavigationEngine.distanceText(nav.remainingDistance))", symbol: "flag.checkered")
        case .navVoice:
            small("Directions voice", value: store.settings.navVoiceOn ? "On" : "Muted",
                  symbol: store.settings.navVoiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
        default:
            EmptyView()
        }
    }

    private func small(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.title3.weight(.bold)).lineLimit(2).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func toggleVoice() {
        store.settings.navVoiceOn.toggle()
        nav.voiceOn = store.settings.navVoiceOn
        if !nav.voiceOn { VoiceService.shared.stopSpeaking() }
    }
}
