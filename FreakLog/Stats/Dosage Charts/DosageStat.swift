import Foundation

struct DosageStat {
    let last30Days: [DayDosage]
    let last26Weeks: [WeekDosage]
    let last12Months: [MonthDosage]
    let years: [YearDosage]
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
