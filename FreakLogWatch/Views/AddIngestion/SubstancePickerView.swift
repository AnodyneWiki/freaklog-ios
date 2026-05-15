import SwiftUI
import CoreData

struct RecentSubstancesList: View {
    @Binding var path: NavigationPath
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Ingestion.time, ascending: false)],
        animation: .default
    )
    private var recentIngestions: FetchedResults<Ingestion>

    var distinctNames: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for ing in recentIngestions {
            let name = ing.substanceNameUnwrapped
            if !seen.contains(name) {
                seen.insert(name)
                result.append(name)
                if result.count >= 8 { break }
            }
        }
        return result
    }

    var body: some View {
        if distinctNames.isEmpty {
            Text("No recent ingestions")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(distinctNames, id: \.self) { name in
                Button {
                    let lite = SubstanceLite(name: name, color: getColor(for: name))
                    path.append(AddRoute.roa(lite))
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(getColor(for: name).swiftUIColor)
                            .frame(width: 10, height: 10)
                        Text(name)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

struct SubstancePickerView: View {
    @Binding var path: NavigationPath
    @State private var query = ""

    var filtered: [Substance] {
        let all = SubstanceRepo.shared.substances
        guard !query.isEmpty else { return Array(all.prefix(60)) }
        let q = query.lowercased()
        return all.filter { substance in
            substance.name.lowercased().contains(q) ||
            substance.commonNames.contains(where: { $0.lowercased().contains(q) })
        }
        .prefix(60)
        .map { $0 }
    }

    var body: some View {
        List {
            TextField("Search", text: $query)
                .textInputAutocapitalization(.never)
            ForEach(filtered) { substance in
                Button {
                    path.append(AddRoute.roa(SubstanceLite(from: substance)))
                } label: {
                    HStack {
                        Circle()
                            .fill(getColor(for: substance.name).swiftUIColor)
                            .frame(width: 10, height: 10)
                        Text(substance.name)
                    }
                }
            }
        }
        .navigationTitle("Substances")
    }
}
