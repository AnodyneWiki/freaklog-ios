import SwiftUI

// Rows shared by the add and edit ingestion forms

struct ExperiencePickerRow: View {
    @Binding var selectedExperience: Experience?
    @Binding var wantsToForceNewExperience: Bool
    let experiences: [Experience]
    var onSelection: () -> Void = {}

    var body: some View {
        if !experiences.isEmpty {
            NavigationLink {
                ExperiencePickerScreen(
                    selectedExperience: $selectedExperience,
                    wantsToForceNewExperience: $wantsToForceNewExperience,
                    experiences: experiences,
                    onSelection: onSelection
                )
            } label: {
                HStack {
                    Text("Experience")
                    Spacer()
                    Text(selectedExperience?.titleUnwrapped ?? "New Experience")
                }
            }
        }
    }
}

struct ConsumerRow: View {
    let consumerName: String
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Text("Consumer")
            Spacer()
            Button(action: onEdit) {
                Label(Ingestion.storedConsumerName(consumerName) ?? "You", systemImage: "person")
            }
        }
    }
}

struct LocationButton: View {
    let locationName: String?
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            if let locationName {
                Label(locationName, systemImage: "mappin")
            } else {
                Label("Add Location", systemImage: "plus")
            }
        }
    }
}
