import Foundation
import XCTest
@testable import FreakLog

final class TimelineModelTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testPhaseBoundariesAndCurveScaledAmount() throws {
        let timeline = model([route(.oral)])
        let rise = start.addingTimeInterval(90)
        let estimate = try XCTUnwrap(timeline.effectEstimate(at: rise))
        XCTAssertEqual(estimate.phase(at: start)?.phase, .onset)
        XCTAssertEqual(estimate.phase(at: rise)?.phase, .rising)
        XCTAssertEqual(estimate.phase(at: rise)?.transition, start.addingTimeInterval(120))
        XCTAssertEqual(estimate.fractionOfPeak(at: rise), 0.5)
        XCTAssertEqual(estimate.curveScaledAmount(at: rise), 5)
        XCTAssertEqual(estimate.phase(at: start.addingTimeInterval(120))?.phase, .peak)
        XCTAssertEqual(estimate.phase(at: start.addingTimeInterval(180))?.phase, .fading)
        XCTAssertNil(timeline.effectEstimate(at: start.addingTimeInterval(240)))
    }

    func testOverlapsAndUnmodeledEntriesSuppressAttribution() {
        let supported = route(.oral)
        let delayed = route(.insufflated, delay: 60)
        let overlapping = model([supported, delayed])
        XCTAssertNotNil(overlapping.effectEstimate(at: start.addingTimeInterval(30)))
        XCTAssertNil(overlapping.effectEstimate(at: start.addingTimeInterval(90)))
        XCTAssertNotNil(overlapping.effectEstimate(at: start.addingTimeInterval(270)))
        XCTAssertNil(overlapping.singleEffectEstimate)

        var incomplete = delayed
        incomplete.roaDuration = nil
        let uncertain = model([supported, incomplete])
        XCTAssertNotNil(uncertain.effectEstimate(at: start.addingTimeInterval(30)))
        XCTAssertNil(uncertain.effectEstimate(at: start.addingTimeInterval(90)))
    }

    func testMergePreservesRouteTimingsAndUsesOneReferenceScale() {
        let oral = route(.oral)
        let inhaled = route(.inhaled, phaseSeconds: 75)
        let unmerged = model([oral, inhaled])
        let merged = model([oral, inhaled], merges: true)
        XCTAssertTrue(unmerged.supportsCombiningRoutes)
        XCTAssertEqual(unmerged.groupDrawables.count, 2)
        XCTAssertEqual(merged.groupDrawables.count, 1)
        XCTAssertEqual(merged.totalWidth, unmerged.totalWidth)
        XCTAssertEqual(merged.groupDrawables.first?.nonNormalizedHeight, 2)
        XCTAssertNotEqual(unmerged, merged)

        var incompatible = inhaled
        incompatible.commonDose = 30
        let withDifferentReference = model([oral, incompatible], merges: true)
        XCTAssertFalse(withDifferentReference.supportsCombiningRoutes)
        XCTAssertEqual(withDifferentReference.groupDrawables.count, 2)
    }

    func testUnknownUnitsLeaveOutScaledAmountAndPreventMerging() {
        let unknown = route(.oral, units: "mL")
        let known = route(.inhaled, delay: 300)
        let timeline = model([unknown, known], merges: true)
        let time = start.addingTimeInterval(90)
        XCTAssertEqual(timeline.effectEstimate(at: time)?.fractionOfPeak(at: time), 0.5)
        XCTAssertNil(timeline.effectEstimate(at: time)?.curveScaledAmount(at: time))
        XCTAssertFalse(timeline.supportsCombiningRoutes)
        XCTAssertEqual(timeline.groupDrawables.count, 2)
    }

    func testOlderLiveActivityPayloadDecodesWithoutNewPreferencesOrUnits() throws {
        let state = TimelineWidgetAttributes.ContentState(
            substanceGroups: [SubstanceIngestionGroup(substanceName: "Example", color: .blue, routeMinInfos: [route(.oral)])],
            everythingForEachRating: [], everythingForEachTimedNote: [],
            areRedosesDrawnIndividually: true, areSubstanceHeightsIndependent: true
        )
        let encoded = try JSONEncoder().encode(state)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var substances = try XCTUnwrap(payload["substanceGroups"] as? [[String: Any]])
        var routes = try XCTUnwrap(substances[0]["routeMinInfos"] as? [[String: Any]])
        var ingestions = try XCTUnwrap(routes[0]["ingestions"] as? [[String: Any]])
        ingestions[0].removeValue(forKey: "doseUnits")
        routes[0]["ingestions"] = ingestions
        routes[0].removeValue(forKey: "commonDoseUnits")
        substances[0]["routeMinInfos"] = routes
        payload["substanceGroups"] = substances
        let oldPayload = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(TimelineWidgetAttributes.ContentState.self, from: oldPayload)
        XCTAssertNil(decoded.combinesComparableRoutes)
        XCTAssertNotNil(decoded.timelineModel.singleEffectEstimate)
    }

    private func route(_ route: AdministrationRoute, delay: TimeInterval = 0, phaseSeconds: Double = 60, units: String = "mg") -> RouteMinInfo {
        let phase = DurationRange(min: phaseSeconds, max: phaseSeconds, units: .seconds)
        return RouteMinInfo(
            route: route,
            ingestions: [IngestionMinInfo(dose: 10, time: start.addingTimeInterval(delay), endTime: nil, onsetDelayInHours: 0, doseUnits: units)],
            roaDuration: RoaDuration(onset: phase, comeup: phase, peak: phase, offset: phase, total: nil, afterglow: nil),
            commonDose: 10,
            commonDoseUnits: "mg"
        )
    }

    private func model(_ routes: [RouteMinInfo], merges: Bool = false) -> TimelineModel {
        TimelineModel(
            substanceGroups: [SubstanceIngestionGroup(substanceName: "Example", color: .blue, routeMinInfos: routes)],
            everythingForEachRating: [], everythingForEachTimedNote: [],
            areRedosesDrawnIndividually: true, areSubstanceHeightsIndependent: false,
            combinesComparableRoutes: merges
        )
    }
}
