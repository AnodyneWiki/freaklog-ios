import SwiftUI

struct AddLocationScreen: View {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var experience: Experience

    var body: some View {
        ChooseLocationScreen(
            locationManager: locationManager,
            initialLocation: nil,
            onDone: onDone
        )
    }

    private func onDone(_ location: Location?) {
        if let location {
            let newLocation = ExperienceLocation.make(from: location, in: PersistenceController.shared.viewContext)
            newLocation.legacyExperience = experience
            PersistenceController.shared.saveViewContext()
        }
    }
}
