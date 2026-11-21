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
            locationManager.selectLocation(experienceLocation.asLocation)
        }
    }

    private func onDone() {
        if let selectedLocation = locationManager.selectedLocation {
            experienceLocation.update(from: selectedLocation)
        } else {
            PersistenceController.shared.viewContext.delete(experienceLocation)
        }
        PersistenceController.shared.saveViewContext()
    }
}
