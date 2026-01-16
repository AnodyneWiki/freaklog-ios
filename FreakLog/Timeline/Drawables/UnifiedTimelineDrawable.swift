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
    
    // MARK: - Width Calculation
    var endOfLineRelativeToStartInSeconds: TimeInterval {
        var duration: TimeInterval = onsetDelayInSeconds
        
        // Accumulate known phases
        if let onset { duration += onset.interpolateLinearly(at: onsetWeight) }
        if let comeup { duration += comeup.interpolateLinearly(at: comeupWeight) }
        if let peak { duration += peak.interpolateLinearly(at: peakWeight) }
        if let offset { duration += offset.interpolateLinearly(at: offsetWeight) }
        
        // If total is present and exceeds the sum of parts, use it
        if let total {
            let totalDur = total.interpolateLinearly(at: totalWeight)
            if totalDur > (duration - onsetDelayInSeconds) {
                duration = onsetDelayInSeconds + totalDur
            }
        }
        
        return ingestionTimeRelativeToStartInSeconds + duration
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
        
        // Calculate Top Y
        var topY = paddingTop
        if normalizedHeight < 1 {
            // Lower height means "higher" y value (since y=0 is top)
            // heightBetween is the available vertical space.
            // (1 - normalizedHeight) * heightBetween gives the empty space from top.
            topY = ((1 - normalizedHeight) * heightBetween) + paddingTop
        }
        
        // --- 1. Draw Dot at Start ---
        context.drawDot(x: startX, bottomY: bottomY, color: color)
        
        // --- 2. Calculate Segments ---
        var currentX = startX
        var currentY = bottomY
        
        var solidPath = Path()
        solidPath.move(to: CGPoint(x: currentX, y: currentY))
        
        // Onset
        if let onset {
            let duration = onset.interpolateLinearly(at: onsetWeight)
            let endX = currentX + (duration * pixelsPerSec)
            // Onset is usually drawn flat at bottom
            solidPath.addLine(to: CGPoint(x: endX, y: bottomY))
            currentX = endX
            currentY = bottomY
        }
        
        // Comeup
        if let comeup {
            let duration = comeup.interpolateLinearly(at: comeupWeight)
            let endX = currentX + (duration * pixelsPerSec)
            // Comeup goes from bottom to top
            solidPath.addLine(to: CGPoint(x: endX, y: topY))
            currentX = endX
            currentY = topY
        }
        
        // Peak
        if let peak {
            let duration = peak.interpolateLinearly(at: peakWeight)
            let endX = currentX + (duration * pixelsPerSec)
            // Peak stays at top
            solidPath.addLine(to: CGPoint(x: endX, y: topY))
            currentX = endX
            currentY = topY
        }
        
        // Offset
        if let offset {
            let duration = offset.interpolateLinearly(at: offsetWeight)
            let endX = currentX + (duration * pixelsPerSec)
            // Offset goes from top to bottom
            solidPath.addLine(to: CGPoint(x: endX, y: bottomY))
            currentX = endX
            currentY = bottomY
        }
        
        // Draw the Solid Part
        context.stroke(solidPath, with: .color(color), style: StrokeStyle.getNormal(lineWidth: lineWidth))
        
        // --- 3. Draw Total / Dotted Part if needed ---
        var dottedPath = Path()
        dottedPath.move(to: CGPoint(x: currentX, y: currentY))
        
        if let total {
            // Calculate total end X
            let totalEndDuration = total.interpolateLinearly(at: totalWeight)
            let totalEndX = startX + (onsetDelayInSeconds * pixelsPerSec) + (totalEndDuration * pixelsPerSec)
            
            if totalEndX > currentX {
                // We have remaining duration to fill with a dotted line
                if currentY < bottomY - 0.1 { // We are at TOP
                    // Curve down to bottom
                    dottedPath.startSmoothLineTo(
                        smoothnessBetween0And1: percentSmoothness,
                        startX: currentX,
                        startY: currentY,
                        endX: totalEndX,
                        endY: bottomY
                    )
                } else { // We are at BOTTOM
                    // Curve Up then Down
                    // Calculate a peak point for the "hump"
                    let remainingWidth = totalEndX - currentX
                    let midX = currentX + (remainingWidth / 2)
                    
                    // Up curve
                    dottedPath.endSmoothLineTo(
                        smoothnessBetween0And1: percentSmoothness,
                        startX: currentX,
                        endX: midX,
                        endY: topY // Go up to max height
                    )
                    // Down curve
                    dottedPath.startSmoothLineTo(
                        smoothnessBetween0And1: percentSmoothness,
                        startX: midX,
                        startY: topY,
                        endX: totalEndX,
                        endY: bottomY
                    )
                }
                
                context.stroke(
                    dottedPath,
                    with: .color(color),
                    style: StrokeStyle.getDotted(lineWidth: lineWidth)
                )
                
                // Add dotted path to solid path for filling
                solidPath.addPath(dottedPath)
                currentX = totalEndX
                currentY = bottomY
            }
        }
        
        // --- 4. Close and Fill ---
        // Ensure we end at bottom for filling
        if abs(currentY - bottomY) > 0.1 {
            solidPath.addLine(to: CGPoint(x: currentX, y: height)) // Should be bottomY usually, but bottomY is height - padding
        }
        
        solidPath.addLine(to: CGPoint(x: currentX, y: height))
        solidPath.addLine(to: CGPoint(x: startX, y: height))
        solidPath.closeSubpath()
        context.fill(solidPath, with: .color(color.opacity(shapeOpacity)))
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
