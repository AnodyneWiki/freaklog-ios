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

// Routes laid out two per row, each linking to the navigation value for that route.
struct RouteGrid<Value: Hashable>: View {
    let routes: [AdministrationRoute]
    let value: (AdministrationRoute) -> Value

    var body: some View {
        let numRows = Int(ceil(Double(routes.count) / 2.0))
        ForEach(0 ..< numRows, id: \.self) { index in
            HStack {
                link(for: routes[index * 2])
                let secondIndex = index * 2 + 1
                if secondIndex < routes.count {
                    link(for: routes[secondIndex])
                }
            }
        }
    }

    private func link(for route: AdministrationRoute) -> some View {
        NavigationLink(value: value(route)) {
            RouteBox(route: route)
        }
    }
}

#Preview {
    RouteBox(route: .oral)
}
