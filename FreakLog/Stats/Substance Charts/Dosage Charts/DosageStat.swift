import Foundation

struct DosageStat {
    let dayDosages: [DayDosage]
    let weekDosages: [WeekDosage]
    let monthDosages: [MonthDosage]
    let yearDosages: [YearDosage]
}

struct DayDosage: Hashable {
    let day: Date
    let dosage: Double
}

struct WeekDosage: Hashable {
    let week: Date
    let dosage: Double
}

struct MonthDosage: Hashable {
    let month: Date
    let dosage: Double
}

struct YearDosage: Hashable {
    let year: Date
    let dosage: Double
}
