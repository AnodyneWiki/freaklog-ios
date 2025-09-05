import SwiftUI

struct ChooseLocationScreen: View {
    @ObservedObject var locationManager: LocationManager
    let onDone: () -> Void
    @Environment(\.dismiss) var dismiss

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
                locationManager.requestPermission()
            }
            locationManager.maybeRequestLocation()
        }
    }

    var doneButton: some View {
        DoneButton {
            onDone()
            dismiss()
        }
    }

    var screen: some View {
        ChooseLocationScreenContent(
            selectedLocation: $locationManager.selectedLocation,
            selectedLocationName: $locationManager.selectedLocationName,
            searchText: $locationManager.searchText,
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
}
