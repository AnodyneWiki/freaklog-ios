import Foundation
import SwiftUI

struct TimelineModel: Hashable {
    static let combinesComparableRoutesKey = "timelineCombinesComparableRoutes"
    static let showsQuantityDetailsKey = "timelineShowsQuantityDetails"

    static func == (lhs: TimelineModel, rhs: TimelineModel) -> Bool {
        lhs.contentHash == rhs.contentHash
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(contentHash)
    }

    // Computed once in init, since equality checks happen on every navigation path diff
    private var contentHash = 0

    let startTime: Date
    let totalWidth: TimeInterval
    let groupDrawables: [GroupDrawable]
    let timeRangeDrawables: [TimeRangeDrawable]
    let ratingDrawables: [RatingDrawable]
    let timedNoteDrawables: [TimedNoteDrawable]
    let axisDrawable: AxisDrawable
    let supportsCombiningRoutes: Bool
    private let effectEstimates: [TimelineEffectEstimate]
    private let unmodeledIngestionTimes: [Date]

    func effectEstimate(at time: Date) -> TimelineEffectEstimate? {
        guard !unmodeledIngestionTimes.contains(where: { $0 <= time }) else { return nil }
        let active = effectEstimates.filter { $0.start <= time && time < $0.end }
        return active.count == 1 ? active.first : nil
    }

    func phaseUpdateDates(from time: Date) -> [Date] {
        let boundaries = effectEstimates.flatMap { [$0.start, $0.onsetEnd, $0.peakStart, $0.peakEnd, $0.end] }
        return [time] + Set(boundaries + unmodeledIngestionTimes).filter { $0 > time }.sorted()
    }

    // A live activity can use a single stable interval without following edits or overlapping curves.
    var singleEffectEstimate: TimelineEffectEstimate? {
        guard unmodeledIngestionTimes.isEmpty, effectEstimates.count == 1 else { return nil }
        return effectEstimates.first
    }

    var timeRange: ClosedRange<Date> {
        startTime...startTime.addingTimeInterval(max(0, totalWidth))
    }

    func clampingTime(_ time: Date) -> Date {
        let range = timeRange
        return min(range.upperBound, max(range.lowerBound, time))
    }

    var isWorthDrawing: Bool {
        let allHaveMissingDuration = groupDrawables.allSatisfy { groupDrawable in
            !groupDrawable.hasDurationInfo
        }
        return !(allHaveMissingDuration && ratingDrawables.isEmpty && timedNoteDrawables.isEmpty)
    }

    struct RoaGroup {
        let color: SubstanceColor
        let roaDuration: RoaDuration?
        let weightedLines: [WeightedLine]
        let ingestionRanges: [IngestionRange]
        let canCombine: Bool
    }

    // swiftlint:disable function_body_length
    init(
        substanceGroups: [SubstanceIngestionGroup],
        everythingForEachRating: [EverythingForOneRating],
        everythingForEachTimedNote: [EverythingForOneTimedNote],
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool,
        visibleTimeRange: ClosedRange<Date>? = nil,
        alignedTimeRange: ClosedRange<Date>? = nil,
        combinesComparableRoutes: Bool = false
    ) {

        let startTime: Date
        let contentStartTime = Self.getStartTime(
            substanceGroups: substanceGroups,
            everythingForEachRating: everythingForEachRating,
            everythingForEachTimedNote: everythingForEachTimedNote
        )
        
        if let alignedTimeRange {
            startTime = alignedTimeRange.lowerBound
        } else if let visibleTimeRange {
            startTime = max(visibleTimeRange.lowerBound, contentStartTime)
        } else {
            startTime = contentStartTime
        }
        self.startTime = startTime

        let substanceGroupsWithRepoInfo = getSubstanceGroupWithRepoInfo(substanceIngestionGroups: substanceGroups)
        var estimates: [TimelineEffectEstimate] = []
        var unmodeled: [Date] = []
        var canCombineRoutes = false
        var groupDrawables: [GroupDrawable] = []
        let roaGroups = zip(substanceGroups, substanceGroupsWithRepoInfo).flatMap { substance, resolvedSubstance in
            let routes = zip(substance.routeMinInfos, resolvedSubstance.routeGroups).map { route, routeGroup in
                let ingestionRanges = routeGroup.ingestions.compactMap { ingestion in
                    if let endTime = ingestion.endTime {
                        IngestionRange(startTime: ingestion.time, endTime: endTime)
                    } else {
                        nil
                    }
                }
                for ingestion in route.ingestions {
                    if let estimate = TimelineEffectEstimate(substance: substance.substanceName, route: route, ingestion: ingestion) {
                        estimates.append(estimate)
                    } else {
                        unmodeled.append(ingestion.time)
                    }
                }
                return RoaGroup(
                    color: resolvedSubstance.color,
                    roaDuration: routeGroup.roaDuration,
                    weightedLines: routeGroup.ingestions.map { ingestion in
                        WeightedLine(
                            startTime: ingestion.time,
                            endTime: ingestion.endTime,
                            horizontalWeight: ingestion.horizontalWeight,
                            strengthRelativeToCommonDose: ingestion.strengthRelativeToCommonDose,
                            onsetDelayInHours: ingestion.onsetDelayInHours
                        )
                    },
                    ingestionRanges: ingestionRanges,
                    canCombine: route.canCombine
                )
            }
            let comparable = routes.filter(\.canCombine)
            let references = substance.routeMinInfos.filter(\.canCombine)
            let referenceUnits = Set(references.compactMap(\.commonDoseUnits))
            let referenceDoses = Set(references.compactMap(\.commonDose))
            let canCombine = comparable.count > 1 && referenceUnits.count == 1 && referenceDoses.count == 1
            canCombineRoutes = canCombineRoutes || canCombine
            let combines = combinesComparableRoutes && canCombine
            if combines {
                groupDrawables.append(GroupDrawable(
                    startGraph: startTime,
                    color: resolvedSubstance.color,
                    combinedRoutes: comparable,
                    areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
                ))
            }
            for group in routes where !combines || !group.canCombine {
                groupDrawables.append(GroupDrawable(
                    startGraph: startTime,
                    color: group.color,
                    roaDuration: group.roaDuration,
                    weightedLines: group.weightedLines,
                    areRedosesDrawnIndividually: areRedosesDrawnIndividually,
                    areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
                ))
            }
            return routes
        }
        supportsCombiningRoutes = canCombineRoutes
        effectEstimates = estimates
        unmodeledIngestionTimes = unmodeled
        // Later ingestion curves are drawn on top.
        groupDrawables.sort { $0.startInSeconds < $1.startInSeconds }
        let maxHeight = groupDrawables.map { group in
            group.nonNormalizedHeight
        }.max() ?? 1
        for (index, _) in groupDrawables.enumerated() {
            groupDrawables[index].normalize(maxHeight: maxHeight)
        }
        self.groupDrawables = groupDrawables
        let intermediateRange = roaGroups.flatMap({ group in
            group.ingestionRanges.map { range in
                let startInSeconds = startTime.distance(to: range.startTime)
                let endInSeconds = startTime.distance(to: range.endTime)
                return TimeRangeDrawable.IntermediateRepresentation(color: group.color, startInSeconds: startInSeconds, endInSeconds: endInSeconds)
            }
        }).sorted { lhs, rhs in
            lhs.rangeInSeconds.lowerBound < rhs.rangeInSeconds.lowerBound
        }
        let timeRangeDrawables = intermediateRange.enumerated().map { index, currentRange in
            let intersectionCount = intermediateRange[..<index].filter {
                $0.rangeInSeconds.overlaps(currentRange.rangeInSeconds)
            }.count
            return TimeRangeDrawable(
                color: currentRange.color,
                startInSeconds: currentRange.rangeInSeconds.lowerBound,
                endInSeconds: currentRange.rangeInSeconds.upperBound,
                intersectionCountWithPreviousRanges: intersectionCount
            )
        }
        self.timeRangeDrawables = timeRangeDrawables
        let ratingDrawables = everythingForEachRating.map { rating in
            RatingDrawable(startGraph: startTime, time: rating.time, option: rating.option)
        }
        self.ratingDrawables = ratingDrawables
        let timedNoteDrawables = everythingForEachTimedNote.map { timedNote in
            TimedNoteDrawable(startGraph: startTime, time: timedNote.time, color: timedNote.color)
        }
        self.timedNoteDrawables = timedNoteDrawables
        let sixHours: TimeInterval = 6 * 60 * 60
        let widthOfTimelinesAndRatings = groupDrawables.map { group in
            group.endRelativeToStartInSeconds
        } + ratingDrawables.map { $0.distanceFromStart } + timedNoteDrawables.map { $0.distanceFromStart } + timeRangeDrawables.map { $0.endInSeconds }
        let calculatedMaxWidth: TimeInterval = (widthOfTimelinesAndRatings.max() ?? sixHours)
        
        let finalWidth: TimeInterval
        if let alignedTimeRange {
            finalWidth = alignedTimeRange.upperBound.timeIntervalSince(startTime)
        } else if let visibleTimeRange {
            let currentTime = visibleTimeRange.upperBound
            let windowDurationFromStart = currentTime.timeIntervalSince(startTime)
            
            let allEndDates = groupDrawables.map {
                startTime.addingTimeInterval($0.endRelativeToStartInSeconds)
            } + ratingDrawables.map {
                startTime.addingTimeInterval($0.distanceFromStart)
            } + timedNoteDrawables.map {
                startTime.addingTimeInterval($0.distanceFromStart)
            } + timeRangeDrawables.map {
                startTime.addingTimeInterval($0.endInSeconds)
            }
            
            let maxEndDate = allEndDates.max()
            let calculatedWidthFromCurrentTime = maxEndDate?.timeIntervalSince(currentTime) ?? sixHours
            
            finalWidth = windowDurationFromStart + max(0, calculatedWidthFromCurrentTime)
        } else {
            finalWidth = calculatedMaxWidth
        }
        
        self.totalWidth = finalWidth
        
        axisDrawable = AxisDrawable(startTime: startTime, widthInSeconds: finalWidth)

        // The drawables follow from these inputs plus the start and width, so hash them instead of the drawables
        var hasher = Hasher()
        hasher.combine(startTime)
        hasher.combine(finalWidth)
        hasher.combine(substanceGroups)
        for rating in everythingForEachRating {
            hasher.combine(rating.time)
            hasher.combine(rating.option)
        }
        for timedNote in everythingForEachTimedNote {
            hasher.combine(timedNote.time)
            hasher.combine(timedNote.color)
        }
        hasher.combine(areRedosesDrawnIndividually)
        hasher.combine(areSubstanceHeightsIndependent)
        hasher.combine(combinesComparableRoutes)
        contentHash = hasher.finalize()
    }
    // swiftlint:enable function_body_length

    private static func getStartTime(
        substanceGroups: [SubstanceIngestionGroup],
        everythingForEachRating: [EverythingForOneRating],
        everythingForEachTimedNote: [EverythingForOneTimedNote]
    ) -> Date {
        let ingestionTimes = substanceGroups.flatMap { group in
            group.routeMinInfos.flatMap { route in
                route.ingestions.map { $0.time }
            }
        }
        let potentialStartTimes = ingestionTimes + everythingForEachRating.map { $0.time } + everythingForEachTimedNote.map { $0.time }
        return potentialStartTimes.min() ?? Date()
    }
}

struct TimelineEffectEstimate {
    enum Phase: String {
        case onset = "Onset"
        case rising = "Come-up"
        case peak = "Peak"
        case fading = "Offset"
    }

    let substance: String
    let route: AdministrationRoute
    let start: Date
    let onsetEnd: Date
    let peakStart: Date
    let peakEnd: Date
    let end: Date
    private let recordedAmount: Double?
    let amountUnit: String?

    init?(substance: String, route: RouteMinInfo, ingestion: IngestionMinInfo) {
        guard ingestion.endTime == nil, let durations = route.roaDuration?.fullPhases,
              ingestion.onsetDelayInHours.isFinite, ingestion.onsetDelayInHours >= 0,
              ingestion.horizontalWeight.isFinite, (0...1).contains(ingestion.horizontalWeight),
              [durations.onset, durations.comeup, durations.peak, durations.offset].allSatisfy({
                  $0.min.isFinite && $0.max.isFinite && $0.min >= 0 && $0.max >= $0.min
              }) else { return nil }
        self.substance = substance
        self.route = route.route
        start = ingestion.time
        onsetEnd = start.addingTimeInterval(ingestion.onsetDelayInHours * 3600 + durations.onset.interpolateLinearly(at: 0.5))
        peakStart = onsetEnd.addingTimeInterval(durations.comeup.interpolateLinearly(at: 0.5))
        peakEnd = peakStart.addingTimeInterval(durations.peak.interpolateLinearly(at: ingestion.horizontalWeight))
        end = peakEnd.addingTimeInterval(durations.offset.interpolateLinearly(at: ingestion.horizontalWeight))
        guard peakStart < end, end.timeIntervalSinceReferenceDate.isFinite else { return nil }
        if let units = route.commonDoseUnits, units == ingestion.doseUnits,
           let dose = ingestion.dose, dose.isFinite, dose > 0 {
            recordedAmount = dose
            amountUnit = units
        } else {
            recordedAmount = nil
            amountUnit = nil
        }
    }

    func phase(at time: Date) -> (phase: Phase, transition: Date)? {
        guard time >= start, time < end else { return nil }
        if time < onsetEnd { return (.onset, onsetEnd) }
        if time < peakStart { return (.rising, peakStart) }
        if time < peakEnd { return (.peak, peakEnd) }
        return (.fading, end)
    }

    func fractionOfPeak(at time: Date) -> Double? {
        guard let phase = phase(at: time)?.phase else { return nil }
        switch phase {
        case .onset: return 0
        case .rising: return time.timeIntervalSince(onsetEnd) / peakStart.timeIntervalSince(onsetEnd)
        case .peak: return 1
        case .fading: return end.timeIntervalSince(time) / end.timeIntervalSince(peakEnd)
        }
    }

    func curveScaledAmount(at time: Date) -> Double? {
        guard let recordedAmount, let fraction = fractionOfPeak(at: time), fraction > 0 else { return nil }
        return recordedAmount * fraction
    }
}
