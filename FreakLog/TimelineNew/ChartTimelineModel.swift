import SwiftUI
import Charts

struct ChartTimelineModel: Hashable {
    static func == (lhs: ChartTimelineModel, rhs: ChartTimelineModel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let id = UUID()
    let startTime: Date
    let totalWidth: TimeInterval
    
    var isWorthDrawing: Bool {
        // It's worth drawing if there are any events (curves, dots), ratings, or notes.
        // The original logic checked if groupDrawables had duration info OR if there were ratings/notes.
        // Here, `series` contains events if there are ingestions (even point ingestions without duration have `ingestionPoints`).
        // So checking if series or events are empty is enough.
        
        let hasSeriesEvents = !series.isEmpty // Any substance group means we at least have ingestion points
        let hasRatings = !ratingEvents.isEmpty
        let hasNotes = !noteEvents.isEmpty
        
        return hasSeriesEvents || hasRatings || hasNotes
    }
    
    // Data for Charts
    let series: [TimelineSeries]
    let ratingEvents: [RatingEvent]
    let noteEvents: [NoteEvent]
    let rangeMedicationEvents: [RangeMedicationEvent] // For IngestionRange (e.g. meds with duration)

    struct TimelineSeries: Identifiable, Hashable {
        let id: String
        let color: Color
        let events: [TimelineEvent] // Points defining the shape
        let ingestionPoints: [ChartPoint] // Points where ingestion occurred with calculated value
    }
    
    struct TimelineEvent: Identifiable, Hashable {
        let id = UUID()
        let points: [ChartPoint]
        let style: EventStyle
    }
    
    enum EventStyle: Hashable {
        case solid // Known duration
        case dashed // Uncertain total
    }

    struct ChartPoint: Identifiable, Hashable {
        let id = UUID()
        let time: Date
        let value: Double
    }
    
    struct RatingEvent: Identifiable, Hashable {
        let id = UUID()
        let time: Date
        let rating: ShulginRatingOption
    }
    
    struct NoteEvent: Identifiable, Hashable {
        let id = UUID()
        let time: Date
        let color: Color
    }
    
    struct RangeMedicationEvent: Identifiable, Hashable {
        let id = UUID()
        let range: Range<Date>
        let color: Color
    }

    init(
        substanceGroups: [SubstanceIngestionGroup],
        everythingForEachRating: [EverythingForOneRating],
        everythingForEachTimedNote: [EverythingForOneTimedNote],
        areRedosesDrawnIndividually: Bool,
        areSubstanceHeightsIndependent: Bool,
        visibleTimeRange: ClosedRange<Date>? = nil
    ) {
        let contentStartTime = ChartTimelineModel.getStartTime(
            substanceGroups: substanceGroups,
            everythingForEachRating: everythingForEachRating,
            everythingForEachTimedNote: everythingForEachTimedNote
        )
        
        let startTime: Date
        if let visibleTimeRange {
            startTime = max(visibleTimeRange.lowerBound, contentStartTime)
        } else {
            startTime = contentStartTime
        }
        self.startTime = startTime
        
        // Prepare Series
        let substanceGroupsWithRepoInfo = getSubstanceGroupWithRepoInfo(substanceIngestionGroups: substanceGroups)
        
        // Calculate Overall Max Strength
        let allIngestions = substanceGroups.flatMap { $0.routeMinInfos.flatMap { $0.ingestions } }
        // We need weighted lines logic to get strength... but IngestionRepo info has it?
        // Wait, getSubstanceGroupWithRepoInfo returns `SubstanceGroupWithRepoInfo` which has `ingestions` with `strengthRelativeToCommonDose`.
        // So we should calculate overall max from `substanceGroupsWithRepoInfo`.
        
        // Actually we do this inside the loop in `getSubstanceGroupWithRepoInfo` logic, but `substanceGroupsWithRepoInfo` is already calculated here.
        // Let's flatten it.
        let allStrengths = substanceGroupsWithRepoInfo.flatMap { group in
            group.routeGroups.flatMap { route in
                route.ingestions.map { $0.strengthRelativeToCommonDose }
            }
        }
        let overallMaxStrength = allStrengths.max() ?? 1.0
        
        var calculatedSeries: [TimelineSeries] = []
        var calculatedRangeEvents: [RangeMedicationEvent] = []
        
        for substanceGroup in substanceGroupsWithRepoInfo {
            for routeGroup in substanceGroup.routeGroups {
                // Collect Ranges
                for ingestion in routeGroup.ingestions {
                    if let endTime = ingestion.endTime {
                        calculatedRangeEvents.append(RangeMedicationEvent(range: ingestion.time..<endTime, color: substanceGroup.color.swiftUIColor))
                    }
                }
                
                // Collect Points/Shapes
                var events: [TimelineEvent] = []
        
                // Calculate Max Height for Normalization
                let roaDuration = routeGroup.roaDuration
                let weightedLines = routeGroup.ingestions.map { ingestion in
                    WeightedLine(
                        startTime: ingestion.time,
                        endTime: ingestion.endTime,
                        horizontalWeight: ingestion.horizontalWeight,
                        strengthRelativeToCommonDose: ingestion.strengthRelativeToCommonDose,
                        onsetDelayInHours: ingestion.onsetDelayInHours
                    )
                }
                let weightedLinesForPointIngestions = weightedLines.filter { $0.endTime == nil }
                
                var maxStrengthOfRoute: Double = 1.0
                
                // Determine if we are drawing cumulative
                let shouldDrawCumulative = !weightedLinesForPointIngestions.isEmpty && !areRedosesDrawnIndividually && (roaDuration?.isFullTimeLineDefined ?? false)
                
                if shouldDrawCumulative {
                    // Calculate Peak of Cumulative Curve
                    if let roaDuration {
                        // Generate non-normalized points to find max value
                        let points = ChartTimelineModel.generatePointsForCumulative(
                            startTime: startTime,
                            weightedLines: weightedLinesForPointIngestions,
                            roaDuration: roaDuration
                        )
                        maxStrengthOfRoute = points.map { $0.value }.max() ?? 1.0
                    }
                } else {
                    maxStrengthOfRoute = weightedLines.map { $0.strengthRelativeToCommonDose }.max() ?? 1.0
                }
                
                let normalizationFactor: Double
                if areSubstanceHeightsIndependent {
                     normalizationFactor = maxStrengthOfRoute
                } else {
                     // Need overall max. We should calculate it before this loop.
                     // IMPORTANT: 'overallMaxStrength' calculated above is currently just max of individual ingestions.
                     // If we want dependent heights to work correctly with cumulative curves, we ideally need the global max of ALL cumulative curves.
                     // For now, let's trust that 'overallMaxStrength' is sufficient for individual, but for cumulative we might still clip if we don't know global cumulative max.
                     // User asked for "upper bound when independent substance heights are enabled".
                     // So we focus on Independent case.
                     normalizationFactor = overallMaxStrength
                }
                

                
                if !weightedLinesForPointIngestions.isEmpty {
                    if areRedosesDrawnIndividually || roaDuration == nil {
                        // Individual lines
                        for line in weightedLinesForPointIngestions {
                            // Normalize the line strength
                            let normalizedLine = WeightedLine(
                                startTime: line.startTime,
                                endTime: line.endTime,
                                horizontalWeight: line.horizontalWeight,
                                strengthRelativeToCommonDose: line.strengthRelativeToCommonDose / normalizationFactor,
                                onsetDelayInHours: line.onsetDelayInHours
                            )
                            
                            if let roaDuration {
                                let points = ChartTimelineModel.generatePointsForUnified(
                                    startTime: startTime,
                                    line: normalizedLine,
                                    roaDuration: roaDuration
                                )
                                events.append(TimelineEvent(points: points, style: .solid))
                                
                                // Dashed part
                                if roaDuration.total != nil {
                                    // Determine where the solid part ended
                                    var dashedStartValue = 0.0
                                    if roaDuration.offset?.maybeFullDurationRange != nil {
                                        dashedStartValue = 0.0
                                    } else if roaDuration.peak?.maybeFullDurationRange != nil {
                                        dashedStartValue = normalizedLine.strengthRelativeToCommonDose
                                    } else if roaDuration.comeup?.maybeFullDurationRange != nil {
                                        dashedStartValue = normalizedLine.strengthRelativeToCommonDose
                                    } else {
                                        dashedStartValue = 0.0
                                    }
                                
                                    let dashedPoints = ChartTimelineModel.generateDashedPoints(
                                        startTime: startTime,
                                        line: normalizedLine,
                                        roaDuration: roaDuration,
                                        startValue: dashedStartValue
                                    )
                                    if !dashedPoints.isEmpty {
                                        events.append(TimelineEvent(points: dashedPoints, style: .dashed))
                                    }
                                }
                            } else {
                                // No duration info
                            }
                        }
                    } else {
                        // Cumulative
                         if let roaDuration,
                            let _ = roaDuration.toFullCumulativeTimeline(
                             weightedLines: weightedLinesForPointIngestions,
                             graphStartTime: startTime,
                             areSubstanceHeightsIndependent: areSubstanceHeightsIndependent
                         ) {
                             // Extract points using normalized lines
                             let normalizedLines = weightedLinesForPointIngestions.map { line in
                                 WeightedLine(
                                     startTime: line.startTime,
                                     endTime: line.endTime,
                                     horizontalWeight: line.horizontalWeight,
                                     strengthRelativeToCommonDose: line.strengthRelativeToCommonDose / normalizationFactor,
                                     onsetDelayInHours: line.onsetDelayInHours
                                 )
                             }
                             
                             let points = ChartTimelineModel.generatePointsForCumulative(
                                 startTime: startTime,
                                 weightedLines: normalizedLines,
                                 roaDuration: roaDuration
                             )
                             events.append(TimelineEvent(points: points, style: .solid))
                         } else {
                             // Fallback to individual
                             for line in weightedLinesForPointIngestions {
                                let normalizedLine = WeightedLine(
                                    startTime: line.startTime,
                                    endTime: line.endTime,
                                    horizontalWeight: line.horizontalWeight,
                                    strengthRelativeToCommonDose: line.strengthRelativeToCommonDose / normalizationFactor,
                                    onsetDelayInHours: line.onsetDelayInHours
                                )
                                 if let roaDuration {
                                     let points = ChartTimelineModel.generatePointsForUnified(
                                         startTime: startTime,
                                         line: normalizedLine,
                                         roaDuration: roaDuration
                                     )
                                     events.append(TimelineEvent(points: points, style: .solid))
                                     
                                     // Dashed part for fallback individual
                                     if roaDuration.total != nil {
                                         var dashedStartValue = 0.0
                                         if roaDuration.offset?.maybeFullDurationRange != nil {
                                             dashedStartValue = 0.0
                                         } else if roaDuration.peak?.maybeFullDurationRange != nil {
                                             dashedStartValue = normalizedLine.strengthRelativeToCommonDose
                                         } else if roaDuration.comeup?.maybeFullDurationRange != nil {
                                             dashedStartValue = normalizedLine.strengthRelativeToCommonDose
                                         } else {
                                             dashedStartValue = 0.0
                                         }
                                         
                                         let dashedPoints = ChartTimelineModel.generateDashedPoints(
                                             startTime: startTime,
                                             line: normalizedLine,
                                             roaDuration: roaDuration,
                                             startValue: dashedStartValue
                                         )
                                         if !dashedPoints.isEmpty {
                                             events.append(TimelineEvent(points: dashedPoints, style: .dashed))
                                         }
                                     }
                                 }
                             }
                         }
                    }
                }
                
                if !events.isEmpty || !weightedLines.isEmpty {
                    // Extract ingestion points with Y-values
                    // We need to look up the Y-value (strength) at each ingestion time.
                    var ingestionChartPoints: [ChartPoint] = []
                    
                    let ingestionTimes = weightedLines.map { $0.startTime }
                    
                    // Helper to find value at time t
                    func getValue(at time: Date) -> Double {
                        // Find the event that covers this time
                        // Prioritize Solid events for main curve, then Dashed?
                        // Actually, for Cumulative, the 'solid' event covers the main timeline.
                        // Iterate through all events points to find segment.
                        
                        // Optimization: For Cumulative, there's usually one big Solid event.
                        // For Individual, there are multiple events.
                        
                        // Simple linear scan (dataset is small)
                        var maxValueAtTime: Double = 0.0
                        
                        for event in events {
                            let points = event.points
                            if let first = points.first, let last = points.last {
                                if time >= first.time && time <= last.time {
                                    // Interpolate
                                    for i in 0..<(points.count - 1) {
                                        let p1 = points[i]
                                        let p2 = points[i+1]
                                        if time >= p1.time && time <= p2.time {
                                            let totalDur = p2.time.timeIntervalSince(p1.time)
                                            if totalDur > 0 {
                                                let progress = time.timeIntervalSince(p1.time) / totalDur
                                                let val = p1.value + (p2.value - p1.value) * progress
                                                maxValueAtTime = max(maxValueAtTime, val)
                                            } else {
                                                maxValueAtTime = max(maxValueAtTime, p1.value)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        return maxValueAtTime
                    }
                    
                    for time in ingestionTimes {
                        let value = getValue(at: time)
                        ingestionChartPoints.append(ChartPoint(time: time, value: value))
                    }
                    
                    calculatedSeries.append(TimelineSeries(id: UUID().uuidString, color: substanceGroup.color.swiftUIColor, events: events, ingestionPoints: ingestionChartPoints))
                }
            }
        }
        
        self.series = calculatedSeries
        self.rangeMedicationEvents = calculatedRangeEvents
        self.ratingEvents = everythingForEachRating.map { RatingEvent(time: $0.time, rating: $0.option) }
        self.noteEvents = everythingForEachTimedNote.map { NoteEvent(time: $0.time, color: $0.color.swiftUIColor) }
        
        // Calculate Total Width
        // Calculate Total Width
        let lastEventTime = series.flatMap { $0.events.flatMap { $0.points.map { $0.time } } }.max() ?? Date.now
        let lastRangeTime = rangeMedicationEvents.map { $0.range.upperBound }.max() ?? Date.now
        let lastItemTime = max(lastEventTime, lastRangeTime)
        let calculatedMaxWidth = lastItemTime.timeIntervalSince(startTime)
        
        let sixHours: TimeInterval = 6 * 60 * 60
        let minWidth = max(calculatedMaxWidth, sixHours)
        
        if let visibleTimeRange {
            let windowDurationFromStart = visibleTimeRange.upperBound.timeIntervalSince(startTime)
            self.totalWidth = max(windowDurationFromStart, minWidth)
        } else {
            self.totalWidth = minWidth
        }
    }
    
    private static var conversationStartTime: Date { .now } // fallback

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
    
    // MARK: - Point Generation Logic
    
    static func generatePointsForUnified(
        startTime: Date,
        line: WeightedLine,
        roaDuration: RoaDuration
    ) -> [ChartPoint] {
        // Trapezoid Logic
        // Onset(Flat) -> Comeup(Up) -> Peak(Flat) -> Offset(Down)
        // Normalized Height
        let height = line.strengthRelativeToCommonDose
        // Scale height if needed? In unified, it uses normalizedHeight but Swift Charts auto-scales Y-axis.
        // We will pass raw value and let chart scale it or fix axis.
        // If we want multiple substances to share scale, we just pass raw values.
        
        var points: [ChartPoint] = []
        
        let onsetDelay = line.onsetDelayInHours * 3600
        let start = line.startTime.addingTimeInterval(onsetDelay)
        points.append(ChartPoint(time: start, value: 0))
        
        var currentTime = start
        
        if let onset = roaDuration.onset?.maybeFullDurationRange {
            let dur = onset.interpolateLinearly(at: 0.5)
            currentTime.addTimeInterval(dur)
            points.append(ChartPoint(time: currentTime, value: 0))
        }
        
        if let comeup = roaDuration.comeup?.maybeFullDurationRange {
            let dur = comeup.interpolateLinearly(at: 0.5) // Using 0.5 as default weight
            currentTime.addTimeInterval(dur)
            points.append(ChartPoint(time: currentTime, value: height))
        }
        
        if let peak = roaDuration.peak?.maybeFullDurationRange {
            let dur = peak.interpolateLinearly(at: line.horizontalWeight)
            currentTime.addTimeInterval(dur)
            points.append(ChartPoint(time: currentTime, value: height))
        }
        
        if let offset = roaDuration.offset?.maybeFullDurationRange {
            let dur = offset.interpolateLinearly(at: line.horizontalWeight)
            currentTime.addTimeInterval(dur)
            points.append(ChartPoint(time: currentTime, value: 0))
        }
        
        return points
    }
    
    static func generateDashedPoints(
        startTime: Date,
        line: WeightedLine,
        roaDuration: RoaDuration,
        startValue: Double // New parameter to know if we start at bottom or top
    ) -> [ChartPoint] {
        guard let total = roaDuration.total?.maybeFullDurationRange else { return [] }
        
        // Calculate where Solid ends
        let onsetDelay = line.onsetDelayInHours * 3600
        var duration: TimeInterval = onsetDelay
        if let onset = roaDuration.onset?.maybeFullDurationRange { duration += onset.interpolateLinearly(at: 0.5) }
        if let comeup = roaDuration.comeup?.maybeFullDurationRange { duration += comeup.interpolateLinearly(at: 0.5) }
        if let peak = roaDuration.peak?.maybeFullDurationRange { duration += peak.interpolateLinearly(at: line.horizontalWeight) }
        if let offset = roaDuration.offset?.maybeFullDurationRange { duration += offset.interpolateLinearly(at: line.horizontalWeight) }
        
        let solidEnd = line.startTime.addingTimeInterval(duration)
        
        let totalDuration = total.interpolateLinearly(at: line.horizontalWeight)
        let solidDurationWithoutDelay = duration - onsetDelay
        if totalDuration <= solidDurationWithoutDelay { return [] }
        
        let totalEnd = line.startTime.addingTimeInterval(onsetDelay + totalDuration)
        
        let startX = solidEnd
        let endX = totalEnd
        let height = line.strengthRelativeToCommonDose
        let steps = 20
        var points: [ChartPoint] = []
        
        // Ensure the FIRST point matches the end of the solid line to prevent gaps
        points.append(ChartPoint(time: startX, value: startValue))
        
        if startValue > 0 {
            // We are at TOP (e.g. no Offset). Curve DOWN to 0.
            // Unified: startSmoothLineTo(startX, startY=height, endX, endY=0)
            // Control point: (startX + (totalEnd - startX)*0.5, height)
            let diff = totalEnd.timeIntervalSince(startX)
            let controlTime = startX.addingTimeInterval(diff * 0.5)
            
            // Quadratic Bezier: P0(start, height), P1(control, height), P2(end, 0)
            for i in 1...steps { // Start from 1 as 0 is already added
                let t = Double(i) / Double(steps)
                let time = startX.timeIntervalSinceReferenceDate + diff * t
                
                // Bezier for Value (Y)
                // y(t) = (1-t)^2 * P0y + 2(1-t)t * P1y + t^2 * P2y
                // P0y = height, P1y = height, P2y = 0
                // y(t) = (1-t)^2*h + 2(1-t)t*h = h((1-t)^2 + 2t - 2t^2) = h(1 - 2t + t^2 + 2t - 2t^2) = h(1 - t^2)
                let val = height * (1 - t * t)
                
                points.append(ChartPoint(time: Date(timeIntervalSinceReferenceDate: time), value: val))
            }
        } else {
            // We are at BOTTOM (e.g. Offset exists, or just Onset). Curve UP then DOWN.
            // Unified: EndSmoothLineTo (Up) -> StartSmoothLineTo (Down)
            // Hump.
            let remainingWidth = totalEnd.timeIntervalSince(solidEnd)
            let midX = solidEnd.addingTimeInterval(remainingWidth / 2)
            
            // First Half: Up
            // P0(start, 0), P1(control, height), P2(mid, height)
            // EndSmoothLineTo: controlX = endX - (diff * smoothness). smoothness=0.5 -> controlX = midX - (midX-start)*0.5 = start + (mid-start)*0.5
            // So control is midpoint of first half. P1y = height.
            
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                // Map t to full time range
                let globalT = t // 0 to 1 over the whole dotted line
                
                if globalT <= 0.5 {
                    // Up Curve (0 to 0.5 normalized time)
                    // Local t (0 to 1) for the first half
                    let localT = globalT * 2
                    let time = startX.timeIntervalSinceReferenceDate + remainingWidth * globalT
                    
                    // Bezier P0(0,0), P1(0.5, h), P2(1, h) ? No.
                    // Unified EndSmoothLineTo targetting (mid, height) from (start, 0).
                    // controlX = mid - (mid-start)*0.5.
                    // Wait, EndSmoothLineTo(startX, endX, endY).
                    // controlX = endX - (endX-startX)*smoothness.
                    // controlY = endY = height.
                    // P0=(start, 0). P1=(control, height). P2=(mid, height).
                    
                    // Bezier 1D for Y:
                    // P0y=0, P1y=height, P2y=height.
                    // y(t) = 2(1-t)t*h + t^2*h = h(2t - 2t^2 + t^2) = h(2t - t^2).
                    // This is Parabola opening down, vertex at t=1 (value h). Correct.
                    
                    let val = height * (2 * localT - localT * localT)
                    points.append(ChartPoint(time: Date(timeIntervalSinceReferenceDate: time), value: val))
                    
                } else {
                    // Down Curve (0.5 to 1.0 normalized time)
                    let localT = (globalT - 0.5) * 2 // 0 to 1
                    let time = startX.timeIntervalSinceReferenceDate + remainingWidth * globalT
                    
                    // StartSmoothLineTo from (mid, height) to (end, 0).
                    // ControlX = mid + (end-mid)*0.5.
                    // ControlY = startY = height.
                    // P0=(mid, height). P1=(control, height). P2=(end, 0).
                    // Identical to logic in "Top" block above.
                    // y(t) = h(1 - t^2).
                    
                    let val = height * (1 - localT * localT)
                    points.append(ChartPoint(time: Date(timeIntervalSinceReferenceDate: time), value: val))
                }
            }
        }
        return points
    }

    static func generatePointsForCumulative(
        startTime: Date,
        weightedLines: [WeightedLine],
        roaDuration: RoaDuration
    ) -> [ChartPoint] {
        guard let onset = roaDuration.onset?.maybeFullDurationRange,
              let comeup = roaDuration.comeup?.maybeFullDurationRange,
              let peak = roaDuration.peak?.maybeFullDurationRange,
              let offset = roaDuration.offset?.maybeFullDurationRange else {
            return []
        }
        
        let graphStartTime = startTime
        
        // Replicate logic from FullCumulativeTimelines.getRangeLineSegments + weightedRelatives
        // Actually FullCumulativeTimelines mixes two things:
        // 1. "weightedRelatives" -> simple trapezoids (convolved?) NO, just linear segments.
        // 2. "rangeLineSegments" -> from FullCumulativeTimelines.getSamplePointsFrom -> calculateExpression
        
        // Wait, look at `FullCumulativeTimelines.init`:
        // It sums up `lineSegments` from `weightedRelatives` (point ingestions) AND `rangeLineSegments`.
        // `weightedRelatives` logic:
        // It creates `LineSegment`s:
        //  - Comeup: (onsetEnd, 0) -> (comeupEnd, height)
        //  - Peak: (comeupEnd, height) -> (peakEnd, height)
        //  - Offset: (peakEnd, height) -> (offsetEnd, 0)
        // These are just trapezoids added together?
        // `pointsWithHeight` sums the height of all segments at each point.
        // So yes, it is just summing the trapezoids!
        
        // So I don't need `calculateExpression` unless I have `weightedLinesForRangeIngestions`?
        // `FullCumulativeTimelines.init` says: `rangeLineSegments = weightedLines.flatMap ... getRangeLineSegments`.
        // `weightedLines` passed to init are "weightedLines".
        // In `TimelineModel`, `FullCumulativeTimelines` is called with checking `weightedLines`?
        // Ah, `TimelineModel` calls `FullCumulativeTimelines` for `weightedLinesForPointIngestions` if NOT drawing individually.
        // So for point ingestions, `weightedLines` will have `endTime == nil`.
        // So `rangeLineSegments` will be EMPTY (because `getSamplePointsFrom` checks `endTime`).
        // So for point ingestions, it is JUST SUMMING TRAPEZOIDS.
        
        // Logic:
        // 1. Generate Trapezoid points for each line
        // 2. Collect all unique X coordinates (critical points: start, onsetEnd, comeupEnd, peakEnd, offsetEnd)
        // 3. Sort X coordinates
        // 4. For each X, sum the Y of all trapezoids.
        
        var criticalPoints: Set<TimeInterval> = []
        var trapezoids: [(startTime: TimeInterval, onsetEnd: TimeInterval, comeupEnd: TimeInterval, peakEnd: TimeInterval, offsetEnd: TimeInterval, height: Double)] = []
        
        for line in weightedLines {
            let onsetAndComeupWeight = 0.5
            let startT = line.startTime.timeIntervalSince(graphStartTime) + line.onsetDelayInHours * 3600
            let onsetT = startT + onset.interpolateLinearly(at: onsetAndComeupWeight)
            let comeupT = onsetT + comeup.interpolateLinearly(at: onsetAndComeupWeight)
            let peakT = comeupT + peak.interpolateLinearly(at: line.horizontalWeight)
            let offsetT = peakT + offset.interpolateLinearly(at: line.horizontalWeight)
            
            criticalPoints.insert(startT)
            criticalPoints.insert(onsetT)
            criticalPoints.insert(comeupT)
            criticalPoints.insert(peakT)
            criticalPoints.insert(offsetT)
            
            trapezoids.append((startT, onsetT, comeupT, peakT, offsetT, line.strengthRelativeToCommonDose))
        }
        
        let sortedX = criticalPoints.sorted()
        var result: [ChartPoint] = []
        
        for x in sortedX {
            var ySum = 0.0
            for trap in trapezoids {
                // Calculate Y at x for this trapezoid
                var y = 0.0
                if x >= trap.onsetEnd && x < trap.comeupEnd {
                    // Rising
                    let progress = (x - trap.onsetEnd) / (trap.comeupEnd - trap.onsetEnd)
                    y = progress * trap.height
                } else if x >= trap.comeupEnd && x < trap.peakEnd {
                    // Peak
                    y = trap.height
                } else if x >= trap.peakEnd && x < trap.offsetEnd {
                    // Falling
                    let progress = (x - trap.peakEnd) / (trap.offsetEnd - trap.peakEnd)
                    y = trap.height * (1 - progress)
                }
                ySum += y
            }
            result.append(ChartPoint(time: graphStartTime.addingTimeInterval(x), value: ySum))
        }
        
        return result
    }
}
