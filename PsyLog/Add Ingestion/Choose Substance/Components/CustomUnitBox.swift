import SwiftUI

struct CustomUnitBox: View {

    let customUnit: CustomUnit

    var body: some View {
        NavigationLink(value: customUnit) {
            NavigatableListItemContent(
                title: "\(customUnit.substanceNameUnwrapped), \(customUnit.nameUnwrapped)") {
                    Text("\(customUnit.doseOfOneUnitDescription) per \(customUnit.unitUnwrapped)")
                }
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct NavigatableListItemContent<Description: View>: View {

    let title: String
    @ViewBuilder let description: () -> Description

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.headline).multilineTextAlignment(.leading)
                description()
                    .multilineTextAlignment(.leading)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.forward")
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 5)
        .padding(.bottom, 10)
    }
}


#Preview {
    NavigationStack {
        CustomUnitBox(customUnit: .previewSample)
        CustomUnitBox(customUnit: .previewSample)
    }
}
