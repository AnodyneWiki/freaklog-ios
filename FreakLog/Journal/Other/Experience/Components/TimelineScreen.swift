import SwiftUI

struct TimelineScreen: View {
    let timelineModel: TimelineModel
    let timeDisplayStyle: TimeDisplayStyle
    @State private var zoomLevel = 1.0
    @State private var isOrientationLandscape = false
    @AppStorage(PersistenceConfiguration.Keys.isEyeOpenKey2) var isEyeOpen: Bool = false

    var body: some View {
        VStack {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack {
                        Spacer()
                        EffectTimeline(
                            timelineModel: timelineModel,
                            height: isOrientationLandscape ? geo.size.height : 300,
                            timeDisplayStyle: timeDisplayStyle
                        )
                        .frame(width: geo.size.width * zoomLevel)
                        Spacer()
                    }
                }
            }
            Slider(value: $zoomLevel, in: 1 ... 6) {
                Text("Zoom Level")
            }
            .padding(.bottom, isOrientationLandscape ? 0 : 100)
            .padding(.horizontal, 30)
        }
        .padding(.horizontal)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            checkCurrentOrientation()
        }
        .onAppear {
            checkCurrentOrientation()
        }
        .navigationTitle("Dose Response")
        .toolbar {
            if isEyeOpen {
                NavigationLink(value: GlobalNavigationDestination.explainExperience) {
                    Label("Timeline Limitations", systemImage: "info.circle")
                }
            }
        }
    }

    private func checkCurrentOrientation() {
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation == .landscapeLeft || deviceOrientation == .landscapeRight {
            isOrientationLandscape = true
        } else if deviceOrientation == .portrait || deviceOrientation == .portraitUpsideDown {
            isOrientationLandscape = false
        }
    }
}

#Preview {
    NavigationStack {
        TimelineScreen(
            timelineModel: TimelineModel(
                substanceGroups: EffectTimeline_Previews.substanceGroups,
                everythingForEachRating: EffectTimeline_Previews.everythingForEachRating,
                everythingForEachTimedNote: EffectTimeline_Previews.everythingForEachTimedNote,
                areRedosesDrawnIndividually: false,
                areSubstanceHeightsIndependent: false
            ),
            timeDisplayStyle: .regular)
    }
}
