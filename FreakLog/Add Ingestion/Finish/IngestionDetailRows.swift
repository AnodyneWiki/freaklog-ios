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
                LabeledContent("Add To", value: selectedExperience?.titleUnwrapped ?? String(localized: "New Experience"))
            }
        }
    }
}

struct ConsumerRow: View {
    let consumerName: String
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            LabeledContent("Logged For", value: Ingestion.storedConsumerName(consumerName) ?? String(localized: "You"))
        }
    }
}

struct LocationButton: View {
    let locationName: String?
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            LabeledContent("Location", value: locationName ?? String(localized: "None"))
        }
    }
}
