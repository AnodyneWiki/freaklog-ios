import SwiftUI

struct CustomSubstanceBox: View {
    let customSubstanceModel: CustomSubstanceModel
    let isEyeOpen: Bool

    var body: some View {
        if isEyeOpen {
            NavigationLink(value: CustomSubstanceChooseRouteScreenArguments(substanceName: customSubstanceModel.name,
                                                                   units: customSubstanceModel.units)) {
                content
            }.overlay(alignment: .bottom) {
                Divider()
            }
        } else {
            NavigationLink(value: CustomChooseDoseScreenArguments(substanceName: customSubstanceModel.name,
                                                                  units: customSubstanceModel.units,
                                                                  administrationRoute: .oral)) {
                content
            }.overlay(alignment: .bottom) {
                Divider()
            }
        }
    }

    private var content: some View {
        NavigatableListItemContent(title: customSubstanceModel.name) {
            Text("custom")
        }
    }
}

#Preview {
    NavigationStack {
        CustomSubstanceBox(
            customSubstanceModel: CustomSubstanceModel(
                name: "Coffee",
                description: "The bitter drink",
                units: "cups"
            ),
            isEyeOpen: true
        )
    }
}
