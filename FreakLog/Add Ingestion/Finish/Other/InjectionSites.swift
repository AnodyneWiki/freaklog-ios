import SwiftUI

enum Nostril: String, CaseIterable, Identifiable {
    case left = "Left Nostril"
    case right = "Right Nostril"
    case both = "Both Nostrils"
    var id: Self { self }
}

enum Vein: String, CaseIterable, Identifiable {
    case leftMedianCubital = "Left Median Cubital"
    case leftCephalic = "Left Cephalic"
    case leftBasilic = "Left Basilic"
    case leftDorsalHand = "Left Dorsal Hand"
    case leftForearm = "Left Median Antebrachial"
    case rightMedianCubital = "Right Median Cubital"
    case rightCephalic = "Right Cephalic"
    case rightBasilic = "Right Basilic"
    case rightDorsalHand = "Right Dorsal Hand"
    case rightForearm = "Right Median Antebrachial"
    case other = "Other"
    var id: Self { self }
}

enum Muscle: String, CaseIterable, Identifiable {
    case leftDeltoid = "Left Deltoid"
    case rightDeltoid = "Right Deltoid"
    case leftVastusLateralis = "Left Vastus Lateralis"
    case rightVastusLateralis = "Right Vastus Lateralis"
    case leftVentrogluteal = "Left Ventrogluteal"
    case rightVentrogluteal = "Right Ventrogluteal"
    case leftDorsogluteal = "Left Dorsogluteal"
    case rightDorsogluteal = "Right Dorsogluteal"
    case leftRectusFemoris = "Left Rectus Femoris"
    case rightRectusFemoris = "Right Rectus Femoris"
    case other = "Other Muscle"
    var id: Self { self }
}

enum SubcutaneousSite: String, CaseIterable, Identifiable {
    case leftAbdomen = "Left Abdomen (Periumbilical)"
    case rightAbdomen = "Right Abdomen (Periumbilical)"
    case leftUpperArm = "Left Posterior Upper Arm"
    case rightUpperArm = "Right Posterior Upper Arm"
    case leftThigh = "Left Anterior Thigh"
    case rightThigh = "Right Anterior Thigh"
    case leftUpperButtock = "Left Upper Buttock"
    case rightUpperButtock = "Right Upper Buttock"
    case other = "Other Site"
    var id: Self { self }
}

// Preserve labels read from imports, including labels outside the picker.
struct AdministrationSiteSelection {
    private var sites: [AdministrationRoute: String] = [:]

    init() {}

    init(route: AdministrationRoute, storedSite: String) {
        self[route] = storedSite
    }

    subscript(route: AdministrationRoute) -> String {
        get { sites[route] ?? "" }
        set { sites[route] = newValue.isEmpty ? nil : newValue }
    }

    func siteString(for route: AdministrationRoute) -> String {
        self[route]
    }
}

struct AdministrationSitePicker: View {
    let route: AdministrationRoute
    @Binding var selection: AdministrationSiteSelection

    var body: some View {
        if let options {
            let storedSite = selection[route]
            Picker(title, selection: Binding(get: { selection[route] }, set: { selection[route] = $0 })) {
                Text("No Site").tag("")
                if !storedSite.isEmpty, !options.contains(storedSite) {
                    Text(storedSite).tag(storedSite)
                }
                ForEach(options, id: \.self) { site in
                    Text(site).tag(site)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var title: LocalizedStringKey {
        switch route {
        case .insufflated: "Nostril"
        case .intravenous: "Injection Vein"
        case .intramuscular: "Injection Muscle"
        default: "Injection Site"
        }
    }

    private var options: [String]? {
        switch route {
        case .insufflated: Nostril.allCases.map(\.rawValue)
        case .intravenous: Vein.allCases.map(\.rawValue)
        case .intramuscular: Muscle.allCases.map(\.rawValue)
        case .subcutaneous: SubcutaneousSite.allCases.map(\.rawValue)
        default: nil
        }
    }
}
