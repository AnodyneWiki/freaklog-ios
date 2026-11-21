import CoreData
import UIKit

@MainActor
func playHapticFeedback() {
    #if !targetEnvironment(simulator)
    let impactMed = UIImpactFeedbackGenerator(style: .medium)
    impactMed.impactOccurred()
    #endif
}

// swiftlint:disable force_cast
func getCurrentAppVersion() -> String {
    return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
}
// swiftlint:enable force_cast

func getColor(for substanceName: String) -> SubstanceColor {
    PersistenceController.shared.getSubstanceCompanion(for: substanceName)?.color ?? SubstanceColor.fallback
}

func getDateFromMillis(millis: UInt64) -> Date {
    let secondsSince1970: TimeInterval = Double(millis) / 1000
    return Date(timeIntervalSince1970: secondsSince1970)
}

func getDate(year: Int, month: Int, day: Int) -> Date? {
    let calendar = Calendar.current
    var dateComponents = DateComponents()
    dateComponents.year = year
    dateComponents.month = month
    dateComponents.day = day
    return calendar.date(from: dateComponents)
}

func getDouble(from text: String) -> Double? {
    decimalFormatter.number(from: text)?.doubleValue
}

private let decimalFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.numberStyle = .decimal
    return formatter
}()
