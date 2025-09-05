import CoreData
@testable import Journal
import XCTest

class DecodingTests: XCTestCase {
    func testRoaDecoding() async throws {
        let data = getInitialData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        decoder.keyDecodingStrategy = .useDefaultKeys
        do {
            let roa = try decoder.decode(RoaDecodable.self, from: data)
            print(roa)
        } catch {
            fatalError(String(describing: error))
        }
    }

    private func getInitialData() -> Data {
        let testBundle = Bundle(for: type(of: self))
        guard let url = testBundle.url(forResource: "Roa", withExtension: "json") else {
            fatalError("Failed to locate Roa.json.")
        }
        guard let data = try? Data(contentsOf: url) else {
            fatalError("Failed to load Roa.json.")
        }
        return data
    }
}

struct RoaDecodable: Decodable {
    let roas: [Roa]

    enum CodingKeys: String, CodingKey {
        case roas
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roas = try container.decode([Roa].self, forKey: .roas)
    }
}
