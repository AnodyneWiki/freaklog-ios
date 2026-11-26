import SwiftUI

struct ExperiencePickerScreen: View {
    @Binding var selectedExperience: Experience?
    @Binding var wantsToForceNewExperience: Bool
    let experiences: [Experience]
    var onSelection: () -> Void = {}
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            Section {
                Button {
                    selectedExperience = nil
                    wantsToForceNewExperience = true
                    onSelection()
                    dismiss()
                } label: {
                    choice(isSelected: selectedExperience == nil) {
                        Text("New Experience")
                    }
                }
            }
            Section("Nearby Experiences") {
                ForEach(experiences) { exp in
                    Button {
                        selectedExperience = exp
                        wantsToForceNewExperience = false
                        onSelection()
                        dismiss()
                    } label: {
                        choice(isSelected: selectedExperience == exp) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exp.titleUnwrapped)
                                if let date = exp.sortDate {
                                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Choose Experience")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choice<Content: View>(
        isSelected: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            content()
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
