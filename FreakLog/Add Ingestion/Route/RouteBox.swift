import SwiftUI

struct RouteRow: View {
    let route: AdministrationRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(route.rawValue.localizedCapitalized)
                .font(.body)
            Text(route.clarification)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        RouteRow(route: .oral)
    }
}
