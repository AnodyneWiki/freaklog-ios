import CoreLocation
import MapKit
import SwiftUI

struct ChooseLocationScreenContent: View {
    let selectedLocation: Location?
    @Binding var selectedLocationName: String
    let selectLocation: (Location?) -> Void
    let authorizationStatus: CLAuthorizationStatus?
    let isLoadingLocationResults: Bool
    let currentLocation: Location?
    let searchSuggestedLocations: [Location]
    let experienceLocations: [Location]
    @Environment(\.isSearching) private var isSearching
    @Environment(\.dismissSearch) private var dismissSearch

    var body: some View {
        List {
            if isSearching {
                if isLoadingLocationResults {
                    ProgressView()
                } else {
                    Section {
                        if searchSuggestedLocations.isEmpty {
                            Text("No Results")
                        } else {
                            ForEach(searchSuggestedLocations) { location in
                                Button {
                                    withAnimation {
                                        selectLocation(location)
                                        dismissSearch()
                                    }
                                } label: {
                                    Label(location.name, systemImage: "mappin")
                                }
                            }
                        }
                    }
                }
            } else {
                Section("Selected Location") {
                    TextField("Name", text: $selectedLocationName, prompt: Text("Enter Name"))
                    if let lat = selectedLocation?.latitude, let long = selectedLocation?.longitude {
                        let pinLocation = CLLocationCoordinate2D(latitude: lat, longitude: long)
                        ZStack(alignment: .topTrailing) {
                            ExperienceLocationMap(coordinate: pinLocation)
                                .id(pinLocation.id)
                                .frame(height: 200)
                            Button {
                                withAnimation {
                                    selectLocation(Location(name: selectedLocationName, longitude: nil, latitude: nil))
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(.systemGray5))
                                        .frame(width: 25)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                                .padding(8)
                                .contentShape(Circle())
                            }
                            .accessibilityLabel(Text("Delete Coordinates"))
                        }
                        .listRowInsets(EdgeInsets())
                    }
                    if selectedLocation != nil {
                        Button {
                            selectLocation(nil)
                        } label: {
                            Label("Delete Location", systemImage: "trash").foregroundColor(.red)
                        }
                    }
                }
                if !experienceLocations.isEmpty || currentLocation != nil {
                    Section("Suggestions") {
                        if let currentLocation {
                            Button {
                                withAnimation {
                                    selectLocation(currentLocation)
                                }
                            } label: {
                                Label("Current Location", systemImage: "location")
                            }
                        }
                        ForEach(experienceLocations) { location in
                            Button {
                                withAnimation {
                                    selectLocation(location)
                                }
                            } label: {
                                Label(location.name, systemImage: "clock.arrow.circlepath")
                            }
                        }
                    }
                }
            }
            if authorizationStatus != .authorizedWhenInUse && authorizationStatus != .authorizedAlways {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Section {
                        Button {
                            Task {
                                await UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Enable Location Access", systemImage: "gearshape")
                        }
                    } footer: {
                        Text("Enable location access in settings to add locations to your experiences automatically.")
                    }
                }
            }
        }
    }
}

extension CLLocationCoordinate2D: @retroactive Identifiable {
    public var id: String {
        "\(latitude)-\(longitude)"
    }
}

struct ExperienceLocationMap: View {
    let coordinate: CLLocationCoordinate2D
    @State private var region: MKCoordinateRegion

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        _region = State(initialValue: MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        ))
    }

    var body: some View {
        Map(coordinateRegion: $region, annotationItems: [coordinate]) {
            MapMarker(coordinate: $0)
        }
    }
}

#Preview {
    ChooseLocationScreenContent(
        selectedLocation: Location(name: "Zurich", longitude: 2, latitude: 2),
        selectedLocationName: .constant(""),
        selectLocation: { _ in },
        authorizationStatus: .denied,
        isLoadingLocationResults: false,
        currentLocation: nil,
        searchSuggestedLocations: [
            Location(name: "Street Name 1", longitude: 2, latitude: 2),
            Location(name: "Street Name 2", longitude: 2, latitude: 2),
            Location(name: "Street Name 3", longitude: 2, latitude: 2),
        ],
        experienceLocations: [
            Location(name: "Home", longitude: 2, latitude: 2),
            Location(name: "Festival", longitude: 2, latitude: 2),
        ]
    )
}
