import SwiftUI

struct OneRoaDurationRow: View {
    let duration: RoaDuration
    let color: SubstanceColor

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if let onset = duration.onset?.displayString {
                    DurationChip(name: "onset", text: onset, color: color)
                }
                if let comeup = duration.comeup?.displayString {
                    DurationChip(name: "comeup", text: comeup, color: color)
                }
                if let peak = duration.peak?.displayString {
                    DurationChip(name: "peak", text: peak, color: color)
                }
                if let offset = duration.offset?.displayString {
                    DurationChip(name: "offset", text: offset, color: color)
                }
            }
            HStack {
                if let total = duration.total?.displayString {
                    Text("total: \(total)")
                        .colorBackground(color)
                }
                if let afterglow = duration.afterglow?.displayString {
                    Text("after effects: \(afterglow)")
                        .colorBackground(color)
                }
            }
        }
        .font(.footnote)
    }
}

#Preview {
    NavigationStack {
        List {
            OneRoaDurationRow(
                duration: SubstanceRepo.shared.getSubstance(name: "4-HO-MET")!.getDuration(for: .smoked)!,
                color: .blue
            )
            OneRoaDurationRow(
                duration: SubstanceRepo.shared.getSubstance(name: "MDMA")!.getDuration(for: .oral)!,
                color: .pink
            )
            OneRoaDurationRow(
                duration: SubstanceRepo.shared.getSubstance(name: "LSD")!.getDuration(for: .sublingual)!,
                color: .purple
            )
        }
    }
}
