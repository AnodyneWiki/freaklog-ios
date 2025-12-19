import SwiftUI

struct EditLocationScreen: View {
    @ObservedObject var experienceLocation: ExperienceLocation
    @ObservedObject var locationManager: LocationManager

    var body: some View {
        ChooseLocationScreen(
            locationManager: locationManager,
            onDone: onDone
        )
        .onAppear {
            locationManager.selectedLocation = Location(
                name: experienceLocation.nameUnwrapped,
                longitude: experienceLocation.longitudeUnwrapped,
                latitude: experienceLocation.latitudeUnwrapped
            )
            locationManager.selectedLocationName = experienceLocation.nameUnwrapped
        }
    }

    private func onDone() {
        if let selectedLocation = locationManager.selectedLocation {
            experienceLocation.name = selectedLocation.name
            experienceLocation.latitude = selectedLocation.latitude ?? 0
            experienceLocation.longitude = selectedLocation.longitude ?? 0
        } else {
            PersistenceController.shared.viewContext.delete(experienceLocation)
        }
        PersistenceController.shared.saveViewContext()
    }
}
