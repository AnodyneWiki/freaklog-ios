import SwiftUI

struct StomachFullnessPicker: View {

    @Binding var stomachFullness: StomachFullness

    var body: some View {
        Picker("Stomach", selection: $stomachFullness) {
            ForEach(StomachFullness.allCases) { option in
                HStack {
                    Text(option.text)
                    Spacer()
                    Text("~\(option.onsetDelayForOralInHours.asRoundedReadableString) hours delay").foregroundColor(.secondary)
                }
            }
        }
    }
}


#Preview {
    List {
        StomachFullnessPicker(stomachFullness: .constant(.empty))
    }
}
