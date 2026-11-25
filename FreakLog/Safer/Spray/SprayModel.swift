import Foundation

struct SprayModel: Identifiable, Equatable {
    var id: String {
        spray?.objectID.uriRepresentation().absoluteString ?? "\(name)|\(numSprays)|\(contentInMl)"
    }

    let name: String
    let numSprays: Double
    let contentInMl: Double
    let spray: Spray?

    var isValid: Bool {
        numSprays.isFinite && numSprays > 0 && contentInMl.isFinite && contentInMl > 0
    }
}

enum SprayCalculation: Hashable {
    case soluteWeight
    case liquidVolume

    static func positiveNumber(_ text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        var value: AnyObject?
        var range = NSRange(input.startIndex..<input.endIndex, in: input)
        let fullRange = range
        guard !input.isEmpty,
              (try? formatter.getObjectValue(&value, for: input, range: &range)) != nil,
              range == fullRange, let number = (value as? NSNumber)?.doubleValue,
              number.isFinite, number > 0 else { return nil }
        return number
    }

    func result(knownQuantity: Double, weightPerSpray: Double, spray: SprayModel) -> Double? {
        guard spray.isValid, knownQuantity.isFinite, knownQuantity > 0,
              weightPerSpray.isFinite, weightPerSpray > 0 else { return nil }
        let calculated: Double
        switch self {
        case .soluteWeight:
            calculated = knownQuantity / spray.contentInMl * spray.numSprays * weightPerSpray
        case .liquidVolume:
            calculated = knownQuantity / weightPerSpray / spray.numSprays * spray.contentInMl
        }
        return calculated.isFinite && calculated > 0 ? calculated : nil
    }

    static func adjustedWeight(_ weight: Double, purity: Double) -> Double? {
        guard weight.isFinite, weight > 0, purity.isFinite, purity > 0, purity <= 100 else { return nil }
        let adjusted = weight / (purity / 100)
        return adjusted.isFinite && adjusted > 0 ? adjusted : nil
    }
}
