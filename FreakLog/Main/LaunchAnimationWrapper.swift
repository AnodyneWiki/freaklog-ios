import SwiftUI

struct LaunchAnimationWrapper<Content: View>: View {
    @ViewBuilder
    public let content: Content
    
    @State
    private var showContent: Bool = false
    
    // The launch screen's eye blinks: it shows closed and fades back open before the content appears
    @State
    private var isEyeOpen: Bool = false
    
    public var body: some View {
        if (showContent) {
            content
        }
        else {
            ZStack {
                Rectangle().fill(.background)
                ZStack {
                    Image("Eye Closed")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    Image("Eye Open")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(isEyeOpen ? 1 : 0)
                }
                .onAppear {
                    withAnimation(.timingCurve(0.1, 0.9, 0.2, 1, duration: 0.75)) {
                        isEyeOpen = true
                    }

                    withAnimation(.easeInOut.delay(0.375)) {
                        showContent = true
                    }
                }
                .frame(width: 150, height: 150, alignment: .center)
            }
            .ignoresSafeArea()
        }
    }
}
