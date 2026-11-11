import CoreLocation
import MapKit
import SwiftUI

/// What a postcode search, address entry or map pin produced.
struct PickedPlace: Equatable {
    var name: String = ""
    var address: String = ""
    var postcode: String = ""
    var latitude: Double?
    var longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Address fields from an Apple Maps placemark.
    static func from(_ pm: CLPlacemark, name: String? = nil) -> PickedPlace {
        let street = [pm.subThoroughfare, pm.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let address = [street, pm.locality ?? pm.subAdministrativeArea ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        return PickedPlace(name: name ?? "", address: address, postcode: pm.postalCode ?? "",
                           latitude: pm.location?.coordinate.latitude, longitude: pm.location?.coordinate.longitude)
    }
}

/// Address block used wherever an address is entered: search by postcode/address/company (Apple Maps),
/// pick from the list, type it by hand, or drop a pin on the map.
struct AddressLookupFields: View {
    @Binding var address: String
    @Binding var postcode: String
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    /// Filled from a search result's name when it is empty (e.g. company / site).
    var name: Binding<String>?
    var addressLabel = "Address"

    @State private var search = AddressSearch()
    @State private var searching = false
    @State private var pinning = false

    var body: some View {
        TextField("Search postcode, address or company", text: Binding(get: { search.query }, set: { search.query = $0; searching = !$0.isEmpty }))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
        if searching {
            ForEach(search.results, id: \.self) { r in
                Button {
                    Task { await choose(r) }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.title).font(.subheadline.weight(.semibold))
                        if !r.subtitle.isEmpty { Text(r.subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .foregroundStyle(.primary)
            }
            if search.results.isEmpty { Text("No matches yet — keep typing, or fill in below.").font(.caption).foregroundStyle(.secondary) }
        }
        VStack(alignment: .leading, spacing: 2) {
            Text(addressLabel).font(.caption).foregroundStyle(.secondary)
            TextField("Street, town", text: $address, axis: .vertical)
        }
        VStack(alignment: .leading, spacing: 2) {
            Text("Postcode").font(.caption).foregroundStyle(.secondary)
            TextField("NN11 8XX", text: Binding(get: { postcode }, set: { postcode = $0.uppercased() }))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
        Button { pinning = true } label: {
            HStack {
                Label(latitude == nil ? "Pinpoint on the map" : "Location pinned — move the pin",
                      systemImage: latitude == nil ? "mappin.and.ellipse" : "mappin.circle.fill")
                Spacer()
                if latitude != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
        .sheet(isPresented: $pinning) {
            MapPinPicker(initial: PickedPlace(name: name?.wrappedValue ?? "", address: address, postcode: postcode,
                                              latitude: latitude, longitude: longitude)) { picked in
                latitude = picked.latitude
                longitude = picked.longitude
                if !picked.address.isEmpty { address = picked.address }
                if !picked.postcode.isEmpty { postcode = picked.postcode }
            }
        }
    }

    private func choose(_ completion: MKLocalSearchCompletion) async {
        searching = false
        guard let item = await search.resolve(completion) else {
            address = [completion.title, completion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
            return
        }
        let pm = item.placemark
        if let name, name.wrappedValue.isEmpty, let n = item.name, n != pm.thoroughfare, !n.contains(pm.postalCode ?? "#") {
            name.wrappedValue = n
        }
        let picked = PickedPlace.from(pm)
        address = picked.address.isEmpty ? (completion.subtitle.isEmpty ? completion.title : completion.subtitle) : picked.address
        postcode = pm.postalCode ?? postcode
        latitude = pm.coordinate.latitude
        longitude = pm.coordinate.longitude
        search.query = ""
    }
}

/// Move the map under a fixed pin to mark the exact spot (yard gate, goods-in, parking bay).
struct MapPinPicker: View {
    @Environment(\.dismiss) private var dismiss
    var initial: PickedPlace
    var onPick: (PickedPlace) -> Void

    @State private var position: MapCameraPosition
    @State private var center: CLLocationCoordinate2D?
    @State private var found = PickedPlace()
    @State private var lookingUp = false
    @State private var satellite = false
    @State private var geocodeTask: Task<Void, Never>?

    init(initial: PickedPlace, onPick: @escaping (PickedPlace) -> Void) {
        self.initial = initial
        self.onPick = onPick
        if let c = initial.coordinate {
            _position = State(initialValue: .region(MKCoordinateRegion(center: c, latitudinalMeters: 600, longitudinalMeters: 600)))
            _center = State(initialValue: c)
        } else {
            _position = State(initialValue: .userLocation(fallback: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 52.5, longitude: -1.5), latitudinalMeters: 400_000, longitudinalMeters: 400_000))))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) {
                    UserAnnotation()
                }
                .mapStyle(satellite ? .hybrid(elevation: .flat) : .standard(pointsOfInterest: .all))
                .mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }
                .onMapCameraChange(frequency: .onEnd) { ctx in
                    center = ctx.region.center
                    lookup(ctx.region.center)
                }
                // Fixed pin in the middle: move the map under it.
                VStack(spacing: 0) {
                    Image(systemName: "mappin")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.red)
                        .shadow(radius: 2)
                    Circle().fill(.black.opacity(0.35)).frame(width: 8, height: 4)
                }
                .offset(y: -20)
                .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    if lookingUp {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(found.address.isEmpty ? "Move the map so the pin is on the exact spot" : found.address)
                            .font(.subheadline.weight(.semibold))
                        if !found.postcode.isEmpty { Text(found.postcode).font(.caption).foregroundStyle(.secondary) }
                    }
                    if let center {
                        Text(String(format: "%.5f, %.5f", center.latitude, center.longitude))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Button {
                        guard let center else { return }
                        var picked = found
                        picked.latitude = center.latitude
                        picked.longitude = center.longitude
                        onPick(picked)
                        dismiss()
                    } label: {
                        Label("Use this spot", systemImage: "mappin.and.ellipse").frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(center == nil)
                }
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle("Pinpoint location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { satellite.toggle() } label: { Image(systemName: satellite ? "map" : "globe.europe.africa.fill") }
                        .accessibilityLabel(satellite ? "Map view" : "Satellite view")
                }
            }
            .task {
                if initial.coordinate == nil, !initial.fullText.isEmpty,
                   let pm = try? await CLGeocoder().geocodeAddressString(initial.fullText).first, let loc = pm.location {
                    position = .region(MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
                }
            }
        }
    }

    private func lookup(_ c: CLLocationCoordinate2D) {
        geocodeTask?.cancel()
        geocodeTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            lookingUp = true
            let pm = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
            lookingUp = false
            if let pm { found = PickedPlace.from(pm) }
        }
    }
}

extension PickedPlace {
    var fullText: String { [address, postcode].filter { !$0.isEmpty }.joined(separator: ", ") }
}
