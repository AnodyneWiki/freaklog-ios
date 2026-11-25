import SwiftUI

struct ExperiencePickerScreen: View {
    @Binding var selectedExperience: Experience?
    @Binding var wantsToForceNewExperience: Bool
    let experiences: [Experience]
    var onSelection: () -> Void = {}
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            Section("Create New") {
                Button {
                    selectedExperience = nil
                    wantsToForceNewExperience = true
                    onSelection()
                    dismiss()
                } label: {
                    let label = "Create New Experience"
                    if selectedExperience == nil {
                        HStack {
                            Text(label)
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(label)
                    }
                }
            }
            Section("Close Experiences") {
                ForEach(experiences) { exp in
                    Button {
                        selectedExperience = exp
                        wantsToForceNewExperience = false
                        onSelection()
                        dismiss()
                    } label: {
                        if selectedExperience == exp {
                            HStack {
                                Text(exp.titleUnwrapped)
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        } else {
                            Text(exp.titleUnwrapped)
                        }
                    }
                }
            }
        }.navigationTitle("Choose Experience")
    }
}
