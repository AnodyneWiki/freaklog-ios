import SwiftUI

struct EditLocationScreen: View {
    @ObservedObject var experienceLocation: ExperienceLocation
    @ObservedObject var locationManager: LocationManager

    var body: some View {
        ChooseLocationScreen(
            locationManager: locationManager,
            initialLocation: experienceLocation.asLocation,
            onDone: onDone
        )
    }

    private func onDone(_ location: Location?) {
        if let location {
            experienceLocation.update(from: location)
        } else {
            PersistenceController.shared.viewContext.delete(experienceLocation)
        }
        PersistenceController.shared.saveViewContext()
    }
}
