import SwiftUI

struct RouteBox: View {
    let route: AdministrationRoute

    var body: some View {
        GroupBox {
            VStack(alignment: .center) {
                Text(route.rawValue.localizedCapitalized)
                    .font(.headline)
                Text(route.clarification)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                minHeight: 0,
                maxHeight: .infinity,
                alignment: .center
            )
        }
    }
}

#Preview {
    RouteBox(route: .oral)
}
