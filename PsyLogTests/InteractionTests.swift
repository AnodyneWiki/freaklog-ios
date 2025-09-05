@testable import PsyLog
import XCTest

final class InteractionTests: XCTestCase {
    func testInteractions() throws {
        XCTAssertFalse(InteractionChecker.hasXAndMatches(wordWithX: "Dox", matchWith: "Oxycodone"))
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "MDMA", bName: "Tramadol"), .dangerous)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "MDMA", bName: "Alcohol"), .uncertain)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "MDMA", bName: "Caffeine"), .uncertain)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Nothing", bName: "MDMA"), nil)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Oxycodone", bName: "MDMA"), nil)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Amphetamine", bName: "Dextromethorphan"), .unsafe)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Amphetamine", bName: "DOM"), .unsafe)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Heroin", bName: "Cocaine"), .dangerous)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Heroin", bName: "Grapefruit"), .dangerous)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Heroin", bName: "Nothing"), nil)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Pregabalin", bName: "LSD"), nil)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Grapefruit", bName: "Heroin"), .dangerous)
    }
}
