@testable import FreakLog
import XCTest

final class InteractionTests: XCTestCase {
    func testInteractionSourcesFollowTheMatchedReference() throws {
        let pair = try XCTUnwrap(InteractionChecker.getInteractionBetween(aName: "MDMA", bName: "25I-NBOMe"))
        let reversed = try XCTUnwrap(
            InteractionChecker.getInteractionBetween(aName: pair.bName, bName: pair.aName)
        )

        let sources = InteractionChecker.documentedSources(for: pair).map(\.name)
        XCTAssertFalse(sources.isEmpty)
        XCTAssertEqual(Set(sources), Set(InteractionChecker.documentedSources(for: reversed).map(\.name)))
    }

    func testInteractions() throws {
        XCTAssertFalse(InteractionChecker.hasXAndMatches(wordWithX: "Dox", matchWith: "Oxycodone"))
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "MDMA", bName: "Tramadol"), .dangerous)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "MDMA", bName: "Alcohol"), .uncertain)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "MDMA", bName: "Caffeine"), .uncertain)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Nothing", bName: "MDMA"), nil)
        // Oxycodone lists stimulants as uncertain and MDMA is one
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Oxycodone", bName: "MDMA"), .uncertain)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "MDMA", bName: "25I-NBOMe"), .unsafe)
        XCTAssertTrue(InteractionChecker.hasXAndMatches(wordWithX: "5-MeO-xxT", matchWith: "5-MeO-DMT"))
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Amphetamine", bName: "Dextromethorphan"), .unsafe)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Amphetamine", bName: "DOM"), .unsafe)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Heroin", bName: "Cocaine"), .dangerous)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Heroin", bName: "Grapefruit"), .dangerous)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Heroin", bName: "Nothing"), nil)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Pregabalin", bName: "LSD"), nil)
        XCTAssertEqual(InteractionChecker.getInteractionTypeBetween(aName: "Grapefruit", bName: "Heroin"), .dangerous)
    }
}
