import SwiftUI

struct DosePicker: View {
    let roaDose: RoaDose?
    @Binding var doseMaybe: Double?
    @Binding var selectedUnits: String
    @State private var doseText = ""

    var body: some View {
        VStack(alignment: .leading) {
            let areUnitsDefined = roaDose?.units != nil
            if !areUnitsDefined {
                UnitsPicker(units: $selectedUnits)
                    .padding(.bottom, 10)
            }
            if areUnitsDefined {
                DynamicDoseRangeView(roaDose: roaDose, dose: doseMaybe)
            }
            doseTextFieldWithUnit
        }
        .task {
            if let doseMaybe {
                doseText = doseMaybe.formatted()
            }
        }
    }

    var doseType: DoseRangeType {
        guard !selectedUnits.isEmpty else { return .none }
        guard let dose = doseMaybe else { return .none }
        return roaDose?.getRangeType(for: dose, with: selectedUnits) ?? .none
    }

    private var doseTextFieldWithUnit: some View {
        HStack {
            TextField("Pure Dose", text: $doseText)
                .keyboardType(.decimalPad)
                .foregroundColor(doseType.color)
            Text(selectedUnits)
        }
        .font(.title)
        .onChange(of: doseText) { text in
            doseMaybe = getDouble(from: text)
        }
    }
}

struct DynamicDoseRangeView: View {
    let roaDose: RoaDose?
    let dose: Double?

    var body: some View {
        guard let dose else { return Text(" ") }
        let units = roaDose?.units ?? ""
        if let threshold = roaDose?.lightMin,
           threshold > dose {
            return Text("threshold (\(threshold.formatted()) \(units))")
                .foregroundColor(DoseRangeType.thresh.color)
        } else if let lightMin = roaDose?.lightMin,
                  let lightMax = roaDose?.commonMin,
                  dose >= lightMin && dose < lightMax {
            return Text("light (\(lightMin.formatted()) - \(lightMax.formatted()) \(units))")
                .foregroundColor(DoseRangeType.light.color)
        } else if let commonMin = roaDose?.commonMin,
                  let commonMax = roaDose?.strongMin,
                  dose >= commonMin && dose < commonMax {
            return Text("common (\(commonMin.formatted()) - \(commonMax.formatted()) \(units))")
                .foregroundColor(DoseRangeType.common.color)
        } else if let strongMin = roaDose?.strongMin,
                  let strongMax = roaDose?.heavyMin,
                  dose >= strongMin && dose < strongMax {
            return Text("strong (\(strongMin.formatted()) - \(strongMax.formatted()) \(units))")
                .foregroundColor(DoseRangeType.strong.color)
        } else if let heavyMin = roaDose?.heavyMin,
                  dose >= heavyMin {
            return Text("heavy (\(heavyMin.formatted()) \(units)+)")
                .foregroundColor(DoseRangeType.heavy.color)
        } else {
            return Text(" ")
        }
    }
}
