import CoreData
import Foundation

extension CustomRoa {
  @nonobjc public class func fetchRequest() -> NSFetchRequest<CustomRoa> {
    NSFetchRequest<CustomRoa>(entityName: "CustomRoa")
  }

  @NSManaged public var administrationRoute: String?
  @NSManaged public var afterglowHigh: Double
  @NSManaged public var afterglowLow: Double
  @NSManaged public var comeupHigh: Double
  @NSManaged public var comeupLow: Double
  @NSManaged public var commonDose: Double
  @NSManaged public var doseUnits: String?
  @NSManaged public var heavyDose: Double
  @NSManaged public var lightDose: Double
  @NSManaged public var offsetHigh: Double
  @NSManaged public var offsetLow: Double
  @NSManaged public var onsetHigh: Double
  @NSManaged public var onsetLow: Double
  @NSManaged public var peakHigh: Double
  @NSManaged public var peakLow: Double
  @NSManaged public var strongDose: Double
  @NSManaged public var substanceName: String?
  @NSManaged public var totalHigh: Double
  @NSManaged public var totalLow: Double
  @NSManaged public var customSubstance: CustomSubstance?
}
