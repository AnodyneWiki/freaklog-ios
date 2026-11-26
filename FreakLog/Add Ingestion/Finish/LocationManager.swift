@preconcurrency import CoreLocation //FIXME
import Foundation

@MainActor
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    @Published var currentLocation: Location?
    @Published private(set) var selectedLocation: Location?
    @Published var authorizationStatus: CLAuthorizationStatus?
    @Published private(set) var searchSuggestedLocations: [Location] = []
    @Published private(set) var isSearchingForLocations = false
    @Published var searchText = "" {
        didSet {
            if searchText != oldValue {
                cancelLocationSearch()
                searchSuggestedLocations = []
            }
        }
    }
    @Published var experienceLocations: [Location] = []
    private let searchGeocoder = CLGeocoder()
    private var searchTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        let sortedLocations = PersistenceController.shared.getRecentLocations(limit: 15)
        experienceLocations = sortedLocations.map(\.asLocation).uniqued()
        self.authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func maybeRequestLocation() {
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let foundCLLocation = locations.last else { return }
            let place = await getPlacemark(from: foundCLLocation)
            let location = Location(
                name: place?.subLocality ?? place?.name ?? "Unknown",
                longitude: foundCLLocation.coordinate.longitude,
                latitude: foundCLLocation.coordinate.latitude
            )
            self.currentLocation = location
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        print("Location manager \(error)") // no assertion failure because this is triggered when adding an ingestion with app intent
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let before = self.authorizationStatus
            let after = manager.authorizationStatus
            let didJustNowGivePermission = before == CLAuthorizationStatus.notDetermined && (after == .authorizedWhenInUse || after == .authorizedAlways)
            if didJustNowGivePermission {
                manager.requestLocation()
            }
            self.authorizationStatus = after
        }
    }

    func selectLocation(_ location: Location?) {
        selectedLocation = location
    }

    func searchLocations() {
        cancelLocationSearch()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearchingForLocations = true
        searchTask = Task { [weak self, searchGeocoder] in
            guard !Task.isCancelled else { return }
            let places = (try? await searchGeocoder.geocodeAddressString(query)) ?? []
            guard !Task.isCancelled, let self else { return }
            self.searchSuggestedLocations = places.map { place in
                Location(
                    name: place.name ?? "Unknown",
                    longitude: place.location?.coordinate.longitude,
                    latitude: place.location?.coordinate.latitude
                )
            }
            self.isSearchingForLocations = false
            self.searchTask = nil
        }
    }

    private func cancelLocationSearch() {
        guard let searchTask else { return }
        searchTask.cancel()
        searchGeocoder.cancelGeocode()
        isSearchingForLocations = false
        self.searchTask = nil
    }

    private func getPlacemark(from location: CLLocation) async -> CLPlacemark? {
        let geocoder = CLGeocoder()
        return try? await geocoder.reverseGeocodeLocation(location).first
    }
}

struct Location: Identifiable, Equatable, LocationValue {
    var id: String {
        name
    }

    static func == (lhs: Location, rhs: Location) -> Bool {
        return lhs.id == rhs.id
    }

    let name: String
    let longitude: Double?
    let latitude: Double?
}
