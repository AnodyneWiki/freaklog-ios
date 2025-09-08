import SwiftUI

struct LaunchAnimationWrapper<Content: View>: View {
    @ViewBuilder
    public let content: Content
    
    @State
    private var showContent: Bool = false
    
    @State
    private var width: CGFloat = 17.25
    
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
                    Circle()
                        .fill(.black)
                        .frame(width: width)
                        .onAppear {
                            withAnimation(.timingCurve(0.1, 0.9, 0.2, 1, duration: 0.75)) {
                                self.width = 48
                            }

                            withAnimation(.easeInOut.delay(0.375)) {
                                showContent = true
                            }
                        }
                }
                .frame(width: 150, height: 150, alignment: .center)
            }
            .ignoresSafeArea()
        }
    }
}
