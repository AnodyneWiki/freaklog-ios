import Foundation

extension Int {
    // e.g. for 2.with(unit: "experience") it returns "2 experiences"
    func with(pluralizableUnit: PluralizableUnit) -> String {
        if Double(self).isPlural {
            "\(self) \(pluralizableUnit.plural)"
        } else {
            "\(self) \(pluralizableUnit.singular)"
        }
    }
}

extension Double {
    func with(pluralizableUnit: PluralizableUnit) -> String {
        if isPlural {
            "\(self.asRoundedReadableString) \(pluralizableUnit.plural)"
        } else {
            "\(self.asRoundedReadableString) \(pluralizableUnit.singular)"
        }
    }

    func justUnit(pluralizableUnit: PluralizableUnit) -> String {
        if isPlural {
            pluralizableUnit.plural
        } else {
            pluralizableUnit.singular
        }
    }

    var isPlural: Bool {
        self != 1
    }
}
