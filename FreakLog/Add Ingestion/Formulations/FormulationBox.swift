import SwiftUI

struct FormulationBox: View {
  @ObservedObject var formulation: Formulation

  var body: some View {
    NavigationLink(value: formulation) {
      NavigatableListItemContent(title: formulation.nameUnwrapped) {
        Text(formulation.componentsDescription)
      }
    }
    .overlay(alignment: .bottom) {
      Divider()
    }
  }
}

#Preview {
  NavigationStack {
    FormulationBox(formulation: .previewSample)
  }
}
