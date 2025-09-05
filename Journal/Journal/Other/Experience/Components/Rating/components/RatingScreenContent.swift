import SwiftUI

struct RatingScreenContent: View {
    @Binding var selectedTime: Date
    @Binding var selectedRating: ShulginRatingOption
    let canDefineOverall: Bool
    @Binding var isOverallRating: Bool

    var body: some View {
        Form {
            Section {
                if canDefineOverall {
                    Toggle("Overall Rating", isOn: $isOverallRating.animation()).tint(.accentColor)
                }
                if !isOverallRating {
                    DatePicker(
                        "Time",
                        selection: $selectedTime,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                }
            }
            SelectRatingSection(selectedRating: $selectedRating)
            RatingExplanationSection()
        }
    }
}

#Preview {
    RatingScreenContent(
        selectedTime: .constant(.now),
        selectedRating: .constant(.plus),
        canDefineOverall: true,
        isOverallRating: .constant(false)
    )
}
