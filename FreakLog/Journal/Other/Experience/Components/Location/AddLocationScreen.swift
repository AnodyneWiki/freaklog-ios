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
            locationManager.selectLocation(nil)
        }
    }

    private func onDone() {
        if let selectedLocation = locationManager.selectedLocation {
            let newLocation = ExperienceLocation.make(from: selectedLocation, in: PersistenceController.shared.viewContext)
            newLocation.legacyExperience = experience
            PersistenceController.shared.saveViewContext()
        }
    }
}
