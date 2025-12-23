import Foundation

struct DosageStat {
    let dayDosages: [DosagePoint]
    let weekDosages: [DosagePoint]
    let monthDosages: [DosagePoint]
    let yearDosages: [DosagePoint]
}

struct DosagePoint: Hashable {
    let date: Date
    let dosage: Double
}
