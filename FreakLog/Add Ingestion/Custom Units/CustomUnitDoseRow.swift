import SwiftUI

struct CustomUnitDoseRow: View {

    let customUnit: CustomUnitMinInfo
    let roaDose: RoaDose?

    var body: some View {
        DoseClassificationRow(
            lightMin: convertToNewUnit(oldDose: roaDose?.lightMin),
            commonMin: convertToNewUnit(oldDose: roaDose?.commonMin),
            strongMin: convertToNewUnit(oldDose: roaDose?.strongMin),
            heavyMin: convertToNewUnit(oldDose: roaDose?.heavyMin),
            units: customUnit.unit)
    }

    private func convertToNewUnit(oldDose: Double?) -> String? {
        if let oldDose, let dosePerUnit = customUnit.dosePerUnit, dosePerUnit > 0 {
            (oldDose/dosePerUnit).asRoundedReadableString
        } else {
            nil
        }
    }
}

#Preview {
    CustomUnitDoseRow(
        customUnit: CustomUnit.previewSample.minInfo,
        roaDose: SubstanceRepo.shared.getSubstance(name: "MDMA")!.getDose(for: .oral))
}
