import CoreData
@testable import FreakLog
import XCTest

class DecodingTests: XCTestCase {
    func testGermanPharmacyPackageCodeFormats() {
        XCTAssertEqual(PharmacyPackageCode("03752864")?.digits, "03752864")
        XCTAssertEqual(PharmacyPackageCode.printed(in: "PZN - 03752864")?.digits, "03752864")
        XCTAssertEqual(PharmacyPackageCode.printed(in: "-03752864")?.digits, "03752864")
        XCTAssertEqual(PharmacyPackageCode.barcode("-03752864", symbology: .code39)?.digits, "03752864")
        let ppn = "[)>\u{1E}06\u{1D}9N110375286414\u{1D}S1234\u{1E}\u{04}"
        XCTAssertEqual(PharmacyPackageCode.barcode(ppn, symbology: .dataMatrix)?.digits, "03752864")
        let gs1 = "]d2" + "01" + "04150037528643" + "211234"
        XCTAssertEqual(PharmacyPackageCode.barcode(gs1, symbology: .dataMatrix)?.digits, "03752864")
        XCTAssertEqual(PharmacyPackageCode.barcode("4150037528643", symbology: .ean13)?.digits, "03752864")

        XCTAssertNil(PharmacyPackageCode("03752865"))
        XCTAssertNil(PharmacyPackageCode("00000000"))
        XCTAssertNil(PharmacyPackageCode.printed(in: "03752864"))
        XCTAssertNil(PharmacyPackageCode.printed(in: "PZN 037528640"))
        XCTAssertNil(PharmacyPackageCode.barcode("03752864", symbology: .code39))
        XCTAssertNil(PharmacyPackageCode.barcode("9N110375286415", symbology: .dataMatrix))
        XCTAssertNil(PharmacyPackageCode.barcode("(01)04150037528642", symbology: .dataMatrix))
    }

    @MainActor
    func testRememberedPackageRequiresTheSameProductAndStrength() throws {
        let store = PersistenceController(inMemory: true)
        let context = store.viewContext
        let suite = "PharmacyPackageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let code = try XCTUnwrap(PharmacyPackageCode("03752864"))
        let unit = CustomUnit(context: context)
        unit.substanceName = "Example"
        unit.administrationRoute = "oral"
        unit.unit = "tablet"
        unit.originalUnit = "mg"
        unit.dose = 10
        try context.save()

        PharmacyPackageMatches.remember(code, product: unit, defaults: defaults)
        XCTAssertEqual(PharmacyPackageMatches.productID(for: code, in: context, defaults: defaults), unit.objectID)
        unit.dose = 20
        XCTAssertNil(PharmacyPackageMatches.productID(for: code, in: context, defaults: defaults))
        context.delete(unit)
        try context.save()
        XCTAssertNil(PharmacyPackageMatches.productID(for: code, in: context, defaults: defaults))
    }

    func testPregabalinPackageCode() {
        // The PZN assigned to Heumann's Pregabin 25 mg 14-capsule package.
        XCTAssertEqual(PharmacyPackageCode.barcode("-10785692", symbology: .code39)?.digits, "10785692")
        XCTAssertEqual(PharmacyPackageCode.printed(in: "PZN 10785692")?.digits, "10785692")
    }

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
