import SwiftUI

struct RoaDoseRow: View {
    let roaDose: RoaDose

    var body: some View {
        DoseClassificationRow(
            lightMin: roaDose.lightMin?.formatted(),
            commonMin: roaDose.commonMin?.formatted(),
            strongMin: roaDose.strongMin?.formatted(),
            heavyMin: roaDose.heavyMin?.formatted(),
            units: roaDose.units)
    }
}
