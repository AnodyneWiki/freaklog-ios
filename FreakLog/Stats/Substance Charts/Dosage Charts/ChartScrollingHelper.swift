import SwiftUI
import Charts

extension View {
    @ViewBuilder
    func chartScrollingCompatibility(
        visibleDomainLength: TimeInterval? = nil,
        initialScrollX: Date? = nil
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.chartScrollableAxes(.horizontal)
                .chartScrollingCompatibilityModifiers(visibleDomainLength: visibleDomainLength, initialScrollX: initialScrollX)
        } else {
            self
        }
    }

    @available(iOS 17.0, *)
    @ViewBuilder
    private func chartScrollingCompatibilityModifiers(
        visibleDomainLength: TimeInterval?,
        initialScrollX: Date?
    ) -> some View {
        if let length = visibleDomainLength, let scrollX = initialScrollX {
            self.chartXVisibleDomain(length: length)
                .chartScrollPosition(initialX: scrollX)
        } else if let length = visibleDomainLength {
            self.chartXVisibleDomain(length: length)
        } else if let scrollX = initialScrollX {
            self.chartScrollPosition(initialX: scrollX)
        } else {
            self
        }
    }
}
