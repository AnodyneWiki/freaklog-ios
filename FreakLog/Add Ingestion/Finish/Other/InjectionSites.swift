import SwiftUI

// Keep the existing site strings as identifiers so exports and integrations retain their meaning.
private struct AdministrationSitePreset: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let isSpecific: Bool

    init(_ id: String, _ title: LocalizedStringKey, isSpecific: Bool = false) {
        self.id = id
        self.title = title
        self.isSpecific = isSpecific
    }

    static func options(for route: AdministrationRoute) -> [Self] {
        switch route {
        case .insufflated:
            [
                Self("Left Nostril", "Left"),
                Self("Right Nostril", "Right"),
                Self("Both Nostrils", "Both"),
            ]
        case .intravenous:
            [
                Self("Forearm", "Forearm"),
                Self("Dorsal Hand", "Back of hand"),
                Self("Inner Elbow", "Inner elbow"),
                Self("Median Cubital", "Median cubital vein", isSpecific: true),
                Self("Cephalic", "Cephalic vein", isSpecific: true),
                Self("Basilic", "Basilic vein", isSpecific: true),
                Self("Median Antebrachial", "Median antebrachial vein", isSpecific: true),
            ]
        case .intramuscular:
            [
                Self("Upper Arm", "Upper arm"),
                Self("Thigh", "Thigh"),
                Self("Hip", "Hip"),
                Self("Buttock", "Buttock"),
                Self("Deltoid", "Shoulder (deltoid)", isSpecific: true),
                Self("Vastus Lateralis", "Outer thigh (vastus lateralis)", isSpecific: true),
                Self("Rectus Femoris", "Front of thigh (rectus femoris)", isSpecific: true),
                Self("Ventrogluteal", "Side of hip (ventrogluteal)", isSpecific: true),
                Self("Dorsogluteal", "Upper outer buttock (dorsogluteal)", isSpecific: true),
            ]
        case .subcutaneous:
            [
                Self("Abdomen", "Abdomen"),
                Self("Upper Arm", "Upper arm"),
                Self("Thigh", "Thigh"),
                Self("Upper Buttock", "Upper buttock"),
                Self("Abdomen (Periumbilical)", "Around the navel", isSpecific: true),
                Self("Posterior Upper Arm", "Back of upper arm", isSpecific: true),
                Self("Anterior Thigh", "Front of thigh", isSpecific: true),
            ]
        case .transdermal:
            [
                Self("Abdomen", "Abdomen"),
                Self("Upper Arm", "Upper arm"),
                Self("Thigh", "Thigh"),
                Self("Hip", "Hip"),
                Self("Buttock", "Buttock"),
            ]
        default:
            []
        }
    }
}

private enum AdministrationSiteChoice: Hashable {
    case unknown
    case preset(String)
    case other
}

private enum AdministrationSiteSide: String, CaseIterable, Identifiable {
    case left = "Left"
    case right = "Right"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }
}

private struct AdministrationSiteDraft {
    let choice: AdministrationSiteChoice
    var side: AdministrationSiteSide?
    var otherLabel = ""
    private var unlabeledOther = "Other"

    init(choice: AdministrationSiteChoice = .unknown) {
        self.choice = choice
    }

    init(route: AdministrationRoute, storedSite: String) {
        guard !storedSite.isEmpty else {
            choice = .unknown
            return
        }
        let presets = AdministrationSitePreset.options(for: route)
        if let preset = presets.first(where: { $0.id == storedSite }) {
            choice = .preset(preset.id)
            return
        }
        if route != .insufflated {
            for side in AdministrationSiteSide.allCases {
                let prefix = side.rawValue + " "
                guard storedSite.hasPrefix(prefix) else { continue }
                let region = String(storedSite.dropFirst(prefix.count))
                if presets.contains(where: { $0.id == region }) {
                    choice = .preset(region)
                    self.side = side
                    return
                }
            }
        }
        choice = .other
        if ["Other", "Other Muscle", "Other Site"].contains(storedSite) {
            unlabeledOther = storedSite
        } else {
            otherLabel = storedSite
        }
    }

    var storedSite: String {
        switch choice {
        case .unknown: ""
        case .preset(let name): side.map { "\($0.rawValue) \(name)" } ?? name
        case .other: otherLabel.isEmpty ? unlabeledOther : otherLabel
        }
    }
}

struct AdministrationSiteSelection {
    private var drafts: [AdministrationRoute: AdministrationSiteDraft] = [:]

    init() {}

    init(route: AdministrationRoute, storedSite: String) {
        drafts[route] = AdministrationSiteDraft(route: route, storedSite: storedSite)
    }

    fileprivate subscript(route: AdministrationRoute) -> AdministrationSiteDraft {
        get { drafts[route] ?? AdministrationSiteDraft() }
        set { drafts[route] = newValue }
    }

    func siteString(for route: AdministrationRoute) -> String {
        self[route].storedSite
    }
}

struct AdministrationSitePicker: View {
    let route: AdministrationRoute
    @Binding var selection: AdministrationSiteSelection

    private var draft: Binding<AdministrationSiteDraft> {
        Binding(get: { selection[route] }, set: { selection[route] = $0 })
    }

    private var choice: Binding<AdministrationSiteChoice> {
        Binding(
            get: { selection[route].choice },
            set: { selection[route] = AdministrationSiteDraft(choice: $0) })
    }

    var body: some View {
        let options = AdministrationSitePreset.options(for: route)
        if !options.isEmpty {
            sitePicker(options: options)

            switch selection[route].choice {
            case .preset where route != .insufflated:
                Picker("Side", selection: draft.side) {
                    Text("Unknown").tag(nil as AdministrationSiteSide?)
                    ForEach(AdministrationSiteSide.allCases) { side in
                        Text(side.title).tag(Optional(side))
                    }
                }
                .pickerStyle(.menu)
            case .other:
                TextField("Site description (optional)", text: draft.otherLabel)
                    .textInputAutocapitalization(.sentences)
            default:
                EmptyView()
            }
        }
    }

    private func sitePicker(options: [AdministrationSitePreset]) -> some View {
        let specific = options.filter(\.isSpecific)
        return Picker(title, selection: choice) {
            Text("Unknown").tag(AdministrationSiteChoice.unknown)
            ForEach(options.filter { !$0.isSpecific }) { option in
                Text(option.title).tag(AdministrationSiteChoice.preset(option.id))
            }
            if !specific.isEmpty {
                Section("More Specific Sites") {
                    ForEach(specific) { option in
                        Text(option.title).tag(AdministrationSiteChoice.preset(option.id))
                    }
                }
            }
            Text("Other…").tag(AdministrationSiteChoice.other)
        }
        .pickerStyle(.menu)
    }

    private var title: LocalizedStringKey {
        switch route {
        case .insufflated: "Nostril"
        case .transdermal: "Application Site"
        default: "Injection Site"
        }
    }
}
