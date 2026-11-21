import SwiftUI

struct UnifiedTimelineDrawable: TimelineDrawable {
    // MARK: - Properties
    let onset: FullDurationRange?
    let comeup: FullDurationRange?
    let peak: FullDurationRange?
    let offset: FullDurationRange?
    let total: FullDurationRange?
    
    let onsetDelayInHours: Double
    let ingestionTimeRelativeToStartInSeconds: TimeInterval
    
    let nonNormalizedHeight: Double
    let nonNormalizedMaxOfRoute: Double
    let areSubstanceHeightsIndependent: Bool
    
    // Weights for interpolation
    var onsetWeight: Double = 0.5
    var comeupWeight: Double = 0.5
    var peakWeight: Double = 0.5
    var offsetWeight: Double = 0.5
    var totalWeight: Double = 0.5
    
    // Smoothness for dotted lines
    let percentSmoothness: Double = 0.5
    
    var nonNormalizedOverallMax = 1.0
    
    private var normalizedHeight: Double {
        if areSubstanceHeightsIndependent {
            return nonNormalizedHeight / nonNormalizedMaxOfRoute
        } else {
            return nonNormalizedHeight / nonNormalizedOverallMax
        }
    }
    
    private var onsetDelayInSeconds: TimeInterval {
        onsetDelayInHours * 60 * 60
    }
    
    // MARK: - Shape

    // Which part of the curve is known depends on which phases the substance has data for.
    // Times are in seconds from the end of the onset delay.
    private enum Shape {
        // Onset, comeup, peak and offset: drawn solid, total is ignored
        case full(onsetEnd: Double, comeupEnd: Double, peakEnd: Double, offsetEnd: Double)
        // Solid up to the end of the peak, then a dotted descent until the total ends
        case peakThenTotal(onsetEnd: Double, comeupEnd: Double, peakEnd: Double, totalEnd: Double)
        // Solid up to the end of the comeup, then a dotted curve down until the total ends
        case comeupThenTotal(onsetEnd: Double, comeupEnd: Double, totalEnd: Double)
        // Solid onset, then a dotted hump until the total ends
        case onsetThenTotal(onsetEnd: Double, totalEnd: Double)
        // Dotted hump over the total duration
        case totalOnly(totalEnd: Double)
        // No total and no offset: draw what is known and stop
        case partial(onsetEnd: Double?, comeupEnd: Double?, peakEnd: Double?)
    }

    private var shape: Shape {
        let onsetDuration = onset?.interpolateLinearly(at: onsetWeight)
        let comeupDuration = comeup?.interpolateLinearly(at: comeupWeight)
        let peakDuration = peak?.interpolateLinearly(at: peakWeight)
        let offsetDuration = offset?.interpolateLinearly(at: offsetWeight)
        let totalDuration = total?.interpolateLinearly(at: totalWeight)

        // Inconsistent data can make the known phases outlast the total; then descend
        // for as long as the comeup took (or the onset if there is no comeup).
        func totalEnd(after knownEnd: Double, descent: Double) -> Double {
            guard let totalDuration, totalDuration > knownEnd else { return knownEnd + descent }
            return totalDuration
        }

        guard let onsetDuration else {
            if let totalDuration {
                return .totalOnly(totalEnd: totalDuration)
            }
            return .partial(onsetEnd: nil, comeupEnd: nil, peakEnd: nil)
        }
        guard let comeupDuration else {
            if totalDuration != nil {
                return .onsetThenTotal(
                    onsetEnd: onsetDuration,
                    totalEnd: totalEnd(after: onsetDuration, descent: max(onsetDuration, 60 * 60))
                )
            }
            return .partial(onsetEnd: onsetDuration, comeupEnd: nil, peakEnd: nil)
        }
        let comeupEnd = onsetDuration + comeupDuration
        guard let peakDuration else {
            if totalDuration != nil {
                return .comeupThenTotal(
                    onsetEnd: onsetDuration,
                    comeupEnd: comeupEnd,
                    totalEnd: totalEnd(after: comeupEnd, descent: comeupDuration)
                )
            }
            return .partial(onsetEnd: onsetDuration, comeupEnd: comeupEnd, peakEnd: nil)
        }
        let peakEnd = comeupEnd + peakDuration
        if let offsetDuration {
            return .full(onsetEnd: onsetDuration, comeupEnd: comeupEnd, peakEnd: peakEnd, offsetEnd: peakEnd + offsetDuration)
        }
        if totalDuration != nil {
            return .peakThenTotal(
                onsetEnd: onsetDuration,
                comeupEnd: comeupEnd,
                peakEnd: peakEnd,
                totalEnd: totalEnd(after: peakEnd, descent: comeupDuration)
            )
        }
        return .partial(onsetEnd: onsetDuration, comeupEnd: comeupEnd, peakEnd: peakEnd)
    }

    // MARK: - Width Calculation
    var endOfLineRelativeToStartInSeconds: TimeInterval {
        let end: Double = switch shape {
        case let .full(_, _, _, offsetEnd): offsetEnd
        case let .peakThenTotal(_, _, _, totalEnd), let .comeupThenTotal(_, _, totalEnd),
             let .onsetThenTotal(_, totalEnd), let .totalOnly(totalEnd): totalEnd
        case let .partial(onsetEnd, comeupEnd, peakEnd): peakEnd ?? comeupEnd ?? onsetEnd ?? 0
        }
        return ingestionTimeRelativeToStartInSeconds + onsetDelayInSeconds + end
    }

    // MARK: - Init
    init(
        onset: FullDurationRange? = nil,
        comeup: FullDurationRange? = nil,
        peak: FullDurationRange? = nil,
        offset: FullDurationRange? = nil,
        total: FullDurationRange? = nil,
        onsetDelayInHours: Double,
        ingestionTimeRelativeToStartInSeconds: TimeInterval,
        nonNormalizedHeight: Double,
        nonNormalizedMaxOfRoute: Double,
        areSubstanceHeightsIndependent: Bool,
        // Optional weights overrides
        onsetWeight: Double = 0.5,
        comeupWeight: Double = 0.5,
        peakWeight: Double = 0.5,
        offsetWeight: Double = 0.5,
        totalWeight: Double = 0.5
    ) {
        self.onset = onset
        self.comeup = comeup
        self.peak = peak
        self.offset = offset
        self.total = total
        self.onsetDelayInHours = onsetDelayInHours
        self.ingestionTimeRelativeToStartInSeconds = ingestionTimeRelativeToStartInSeconds
        self.nonNormalizedHeight = nonNormalizedHeight
        self.nonNormalizedMaxOfRoute = nonNormalizedMaxOfRoute
        self.areSubstanceHeightsIndependent = areSubstanceHeightsIndependent
        self.onsetWeight = onsetWeight
        self.comeupWeight = comeupWeight
        self.peakWeight = peakWeight
        self.offsetWeight = offsetWeight
        self.totalWeight = totalWeight
    }

    // MARK: - Drawing
    func draw(
        context: GraphicsContext,
        height: Double,
        pixelsPerSec: Double,
        color: Color,
        lineWidth: Double
    ) {
        let halfLineWidth = lineWidth / 2
        let paddingTop = halfLineWidth
        let paddingBottom = halfLineWidth
        let heightBetween = height - paddingTop - paddingBottom
        let startX = ingestionTimeRelativeToStartInSeconds * pixelsPerSec
        let bottomY = height - paddingBottom
        // Lower height means a larger y value, since y = 0 is the top
        let topY = normalizedHeight < 1 ? ((1 - normalizedHeight) * heightBetween) + paddingTop : paddingTop
        let lineStartX = startX + onsetDelayInSeconds * pixelsPerSec
        func x(_ seconds: Double) -> Double {
            lineStartX + seconds * pixelsPerSec
        }

        // `outline` collects every segment for the fill; solid and dotted segments are stroked separately
        var outline = Path()
        var solid = Path()
        var dotted = Path()
        outline.move(to: CGPoint(x: startX, y: bottomY))
        solid.move(to: CGPoint(x: startX, y: bottomY))

        func solidLine(to x: Double, _ y: Double) {
            solid.addLine(to: CGPoint(x: x, y: y))
            outline.addLine(to: CGPoint(x: x, y: y))
        }
        func dottedLine(to x: Double, _ y: Double) {
            if dotted.isEmpty, let current = outline.currentPoint { dotted.move(to: current) }
            dotted.addLine(to: CGPoint(x: x, y: y))
            outline.addLine(to: CGPoint(x: x, y: y))
        }
        func dottedCurveDown(from fromX: Double, to toX: Double) {
            if dotted.isEmpty, let current = outline.currentPoint { dotted.move(to: current) }
            dotted.startSmoothLineTo(smoothnessBetween0And1: percentSmoothness, startX: fromX, startY: topY, endX: toX, endY: bottomY)
            outline.startSmoothLineTo(smoothnessBetween0And1: percentSmoothness, startX: fromX, startY: topY, endX: toX, endY: bottomY)
        }
        func dottedHump(from fromX: Double, to toX: Double) {
            let midX = fromX + (toX - fromX) / 2
            if dotted.isEmpty, let current = outline.currentPoint { dotted.move(to: current) }
            dotted.endSmoothLineTo(smoothnessBetween0And1: percentSmoothness, startX: fromX, endX: midX, endY: topY)
            outline.endSmoothLineTo(smoothnessBetween0And1: percentSmoothness, startX: fromX, endX: midX, endY: topY)
            dottedCurveDown(from: midX, to: toX)
        }

        solidLine(to: lineStartX, bottomY)
        var endX = lineStartX
        switch shape {
        case let .full(onsetEnd, comeupEnd, peakEnd, offsetEnd):
            solidLine(to: x(onsetEnd), bottomY)
            solidLine(to: x(comeupEnd), topY)
            solidLine(to: x(peakEnd), topY)
            solidLine(to: x(offsetEnd), bottomY)
            endX = x(offsetEnd)
        case let .peakThenTotal(onsetEnd, comeupEnd, peakEnd, totalEnd):
            solidLine(to: x(onsetEnd), bottomY)
            solidLine(to: x(comeupEnd), topY)
            solidLine(to: x(peakEnd), topY)
            dottedLine(to: x(totalEnd), bottomY)
            endX = x(totalEnd)
        case let .comeupThenTotal(onsetEnd, comeupEnd, totalEnd):
            solidLine(to: x(onsetEnd), bottomY)
            solidLine(to: x(comeupEnd), topY)
            dottedCurveDown(from: x(comeupEnd), to: x(totalEnd))
            endX = x(totalEnd)
        case let .onsetThenTotal(onsetEnd, totalEnd):
            solidLine(to: x(onsetEnd), bottomY)
            dottedHump(from: x(onsetEnd), to: x(totalEnd))
            endX = x(totalEnd)
        case let .totalOnly(totalEnd):
            dottedHump(from: lineStartX, to: x(totalEnd))
            endX = x(totalEnd)
        case let .partial(onsetEnd, comeupEnd, peakEnd):
            if let onsetEnd {
                solidLine(to: x(onsetEnd), bottomY)
                endX = x(onsetEnd)
            }
            if let comeupEnd {
                solidLine(to: x(comeupEnd), topY)
                endX = x(comeupEnd)
            }
            if let peakEnd {
                solidLine(to: x(peakEnd), topY)
                endX = x(peakEnd)
            }
        }

        context.stroke(solid, with: .color(color), style: StrokeStyle.getNormal(lineWidth: lineWidth))
        if !dotted.isEmpty {
            context.stroke(dotted, with: .color(color), style: StrokeStyle.getDotted(lineWidth: lineWidth))
        }
        outline.addLine(to: CGPoint(x: endX, y: height))
        outline.addLine(to: CGPoint(x: startX, y: height))
        outline.closeSubpath()
        context.fill(outline, with: .color(color.opacity(shapeOpacity)))
        context.drawDot(x: startX, bottomY: bottomY, color: color)
    }
}

// MARK: - Path Extensions for Smooth Lines
private extension Path {
    mutating func startSmoothLineTo(
        smoothnessBetween0And1: Double,
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double
    ) {
        let diff = endX - startX
        let controlX = startX + (diff * smoothnessBetween0And1)
        addQuadCurve(to: CGPoint(x: endX, y: endY), control: CGPoint(x: controlX, y: startY))
    }

    mutating func endSmoothLineTo(
        smoothnessBetween0And1: Double,
        startX: Double,
        endX: Double,
        endY: Double
    ) {
        let diff = endX - startX
        let controlX = endX - (diff * smoothnessBetween0And1)
        addQuadCurve(to: CGPoint(x: endX, y: endY), control: CGPoint(x: controlX, y: endY))
    }
}
