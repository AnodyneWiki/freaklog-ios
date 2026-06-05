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

struct NostrilPicker: View {
    @Binding var selection: Nostril?

    var body: some View {
        Picker("Nostril", selection: $selection) {
            Text("Select Nostril...").tag(Optional<Nostril>.none)
            ForEach(Nostril.allCases) { option in
                Text(option.rawValue).tag(Optional(option))
            }
        }
    }
}

struct VeinPicker: View {
    @Binding var selection: Vein?

    var body: some View {
        Picker("Injection Vein", selection: $selection) {
            Text("Select Vein...").tag(Optional<Vein>.none)
            ForEach(Vein.allCases) { option in
                Text(option.rawValue).tag(Optional(option))
            }
        }
    }
}

struct MusclePicker: View {
    @Binding var selection: Muscle?

    var body: some View {
        Picker("Injection Muscle", selection: $selection) {
            Text("Select Muscle...").tag(Optional<Muscle>.none)
            ForEach(Muscle.allCases) { option in
                Text(option.rawValue).tag(Optional(option))
            }
        }
    }
}

struct SubQSitePicker: View {
    @Binding var selection: SubcutaneousSite?

    var body: some View {
        Picker("Injection Site", selection: $selection) {
            Text("Select Site...").tag(Optional<SubcutaneousSite>.none)
            ForEach(SubcutaneousSite.allCases) { option in
                Text(option.rawValue).tag(Optional(option))
            }
        }
    }
}

extension AdministrationRoute {
    func siteString(nostril: Nostril?, vein: Vein?, muscle: Muscle?, subQSite: SubcutaneousSite?) -> String {
        switch self {
        case .insufflated: return nostril?.rawValue ?? ""
        case .intravenous: return vein?.rawValue ?? ""
        case .intramuscular: return muscle?.rawValue ?? ""
        case .subcutaneous: return subQSite?.rawValue ?? ""
        default: return ""
        }
    }
}
