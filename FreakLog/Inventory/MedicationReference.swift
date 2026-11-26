import SwiftUI
import UIKit

struct MedicationReferenceSection: View {
    let suggestedName: String
    let pzn: String?
    let allowsNameSuggestions: Bool
    let onPick: (GermanMedication) -> Void

    @State private var selectedMedication: GermanMedication?

    var body: some View {
        Section("Medication Reference") {
            if let medication = selectedMedication, medication.name == suggestedName {
                LabeledContent("Active Ingredients", value: medication.ingredients)
                if !medication.route.isEmpty {
                    LabeledContent("Route", value: medication.route)
                }
            }
            if allowsNameSuggestions {
                NavigationLink {
                    GermanMedicationSearch(initialName: suggestedName) { medication in
                        selectedMedication = medication
                        onPick(medication)
                    }
                } label: {
                    Label("Search Medication Suggestions", systemImage: "magnifyingglass")
                }
            }
            if let pzn {
                PackageReferenceLinks(name: suggestedName, pzn: pzn)
            }
        }
    }
}

struct PackageReferenceLinks: View {
    let name: String
    let pzn: String?

    var body: some View {
        if let url = Self.gelbeListeURL(name: name, pzn: pzn) {
            Link(destination: url) {
                Label("Open in Gelbe Liste", systemImage: "arrow.up.right.square")
            }
        }
        Link(destination: Self.pharmNetURL) {
            Label("Open PharmNet.Bund", systemImage: "arrow.up.right.square")
        }
    }

    static let pharmNetURL = URL(string: "https://www.pharmnet-bund.de/PharmNet/DE/Oeffentlichkeit/Arzneimittel-Informationssystem/_node.html")!

    static func gelbeListeURL(name: String = "", pzn: String? = nil) -> URL? {
        let query = pzn ?? name.trimmingCharacters(in: .whitespacesAndNewlines)
        var url = URLComponents()
        url.scheme = "https"
        url.host = "www.gelbe-liste.de"
        if query.isEmpty {
            url.path = "/fachinformation"
        } else {
            url.path = "/suche"
            url.queryItems = [URLQueryItem(name: "term", value: query)]
        }
        return url.url
    }
}

struct GermanMedication: Hashable, Sendable {
    let name: String
    let ingredients: String
    let route: String
}

private actor GermanMedicationIndex {
    static let shared = GermanMedicationIndex()
    static let source = URL(string: "https://www.ema.europa.eu/en/human-regulatory-overview/post-authorisation/data-medicines-iso-idmp-standards-post-authorisation/public-data-article-57-database")!

    enum LookupError: Error {
        case missingIndex
    }

    struct MatchList: Sendable {
        let medications: [GermanMedication]
        let revision: String
        let snapshot: String
    }

    private struct Entry {
        let medication: GermanMedication
        let nameKey: String
        let ingredientKey: String
    }

    private var entries: [Entry] = []
    private var revision = ""
    private var snapshot = ""

    func search(_ text: String) throws -> MatchList {
        if entries.isEmpty { try load() }
        let query = Self.searchKey(text.trimmingCharacters(in: .whitespacesAndNewlines))
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard query.count >= 2 else {
            return MatchList(medications: [], revision: revision, snapshot: snapshot)
        }

        let maximum = 50
        var prefixes: [GermanMedication] = []
        var names: [GermanMedication] = []
        var ingredients: [GermanMedication] = []
        for entry in entries {
            if entry.nameKey.hasPrefix(query) {
                prefixes.append(entry.medication)
                if prefixes.count == maximum { break }
            } else if names.count < maximum && terms.allSatisfy(entry.nameKey.contains) {
                names.append(entry.medication)
            } else if ingredients.count < maximum && terms.allSatisfy({
                entry.nameKey.contains($0) || entry.ingredientKey.contains($0)
            }) {
                ingredients.append(entry.medication)
            }
        }

        return MatchList(
            medications: Array((prefixes + names + ingredients).prefix(maximum)),
            revision: revision, snapshot: snapshot
        )
    }

    private func load() throws {
        guard let asset = NSDataAsset(name: "GermanMedicines"),
              let text = String(data: asset.data, encoding: .utf8) else { throw LookupError.missingIndex }
        let lines = text.split(separator: "\n")
        guard lines.count > 5 else { throw LookupError.missingIndex }
        revision = String(lines[3])
        snapshot = String(lines[4])
        entries = lines.dropFirst(5).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3 else { return nil }
            let medication = GermanMedication(name: String(fields[0]), ingredients: String(fields[1]), route: String(fields[2]))
            return Entry(medication: medication, nameKey: Self.searchKey(medication.name),
                         ingredientKey: Self.searchKey(medication.ingredients))
        }
        if entries.isEmpty { throw LookupError.missingIndex }
    }

    private static func searchKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de"))
    }
}

private struct GermanMedicationSearch: View {
    let onPick: (GermanMedication) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var matches: GermanMedicationIndex.MatchList?
    @State private var failed = false

    init(initialName: String, onPick: @escaping (GermanMedication) -> Void) {
        _query = State(initialValue: initialName)
        self.onPick = onPick
    }

    var body: some View {
        List {
            Section {
                if failed {
                    Text("The medication index could not be opened.")
                        .foregroundStyle(.secondary)
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    Text("Search by brand or active ingredient.")
                        .foregroundStyle(.secondary)
                } else if let matches {
                    if matches.medications.isEmpty {
                        Text("No matching names.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(matches.medications, id: \.self) { medication in
                            Button {
                                onPick(medication)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(medication.name).foregroundStyle(.primary)
                                    Text(medication.ingredients)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if !medication.route.isEmpty {
                                        Text(medication.route)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            } footer: {
                Text("Selecting a suggestion fills the product name. Confirm the strength and pack size on the label.")
            }

            Section {
                Link(destination: GermanMedicationIndex.source) {
                    Label("European Medicines Agency", systemImage: "arrow.up.right.square")
                }
            } footer: {
                if let matches {
                    Text("Article 57 product data for Germany. \(matches.revision), \(matches.snapshot).")
                }
            }
        }
        .navigationTitle("Medication Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Brand or ingredient")
        .task(id: query) {
            let search = query
            matches = nil
            failed = false
            do {
                try await Task.sleep(for: .milliseconds(150))
                let result = try await GermanMedicationIndex.shared.search(search)
                try Task.checkCancellation()
                matches = result
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
        }
    }
}
