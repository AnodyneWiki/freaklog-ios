import SwiftUI

struct AddLocationScreen: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var experience: Experience

    var body: some View {
        ChooseLocationScreen(
            locationManager: locationManager,
            onDone: onDone
        )
        .onAppear {
            locationManager.selectedLocation = nil
            locationManager.selectedLocationName = ""
        }
    }

    private func onDone() {
        if let selectedLocation = locationManager.selectedLocation {
            let newLocation = ExperienceLocation(context: PersistenceController.shared.viewContext)
            newLocation.name = selectedLocation.name
            newLocation.latitude = selectedLocation.latitude ?? 0
            newLocation.longitude = selectedLocation.longitude ?? 0
            newLocation.legacyExperience = experience
            PersistenceController.shared.saveViewContext()
        }
    }
}
