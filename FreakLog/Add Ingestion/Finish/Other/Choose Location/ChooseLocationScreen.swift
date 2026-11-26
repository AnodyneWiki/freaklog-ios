import SwiftUI

struct ChooseLocationScreen: View {
    @ObservedObject var locationManager: LocationManager
    let onDone: (Location?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftLocation: Location?
    @State private var draftName: String
    @State private var didEditDraft = false
    @State private var isWaitingForFirstLocation = false

    init(locationManager: LocationManager, initialLocation: Location?, onDone: @escaping (Location?) -> Void) {
        self.locationManager = locationManager
        self.onDone = onDone
        _draftLocation = State(initialValue: initialLocation)
        _draftName = State(initialValue: initialLocation?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            screen.toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    doneButton
                }
            }
        }
        .task {
            if locationManager.authorizationStatus == .notDetermined {
                isWaitingForFirstLocation = draftLocation == nil
                locationManager.requestPermission()
            }
            locationManager.maybeRequestLocation()
        }
        .onReceive(locationManager.$currentLocation) { location in
            guard isWaitingForFirstLocation, let location else { return }
            isWaitingForFirstLocation = false
            if !didEditDraft, draftLocation == nil {
                selectLocation(location)
            }
        }
        .onDisappear { locationManager.searchText = "" }
    }

    var doneButton: some View {
        DoneButton {
            onDone(draftLocation)
            dismiss()
        }
        .disabled(draftLocation != nil && draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var screen: some View {
        ChooseLocationScreenContent(
            selectedLocation: draftLocation,
            selectedLocationName: Binding(get: { draftName }, set: renameLocation),
            selectLocation: selectLocation,
            authorizationStatus: locationManager.authorizationStatus,
            isLoadingLocationResults: locationManager.isSearchingForLocations,
            currentLocation: locationManager.currentLocation,
            searchSuggestedLocations: locationManager.searchSuggestedLocations,
            experienceLocations: locationManager.experienceLocations
        )
        .searchable(
            text: $locationManager.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Location"
        )
        .disableAutocorrection(true)
        .scrollDismissesKeyboard(.interactively)
        .onSubmit(of: .search) {
            locationManager.searchLocations()
        }
        .navigationTitle("Experience Location")
    }
    private func selectLocation(_ location: Location?) {
        didEditDraft = true
        draftLocation = location
        draftName = location?.name ?? ""
    }

    private func renameLocation(_ name: String) {
        didEditDraft = true
        draftName = name
        guard !name.isEmpty else { return }
        draftLocation = Location(name: name, longitude: draftLocation?.longitude, latitude: draftLocation?.latitude)
    }

}
