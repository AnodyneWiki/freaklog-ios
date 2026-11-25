import SwiftUI

struct WelcomeScreen: View {
    @Binding var isShowingWelcome: Bool
    @AppStorage(PersistenceController.isEyeOpenKey2) var isEyeOpen: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var imageName: String {
        isEyeOpen ? "Eye Open" : "Eye Closed"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 30) {
                    VStack(spacing: 14) {
                        Image(decorative: imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .padding(.leading, 10)
                            .onTapGesture(count: 3, perform: toggleEye)
                        Text("Welcome to \(appName)")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(features) { feature in
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: feature.image)
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(minWidth: 34)
                                    .padding(.top, 2)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(feature.title)
                                        .font(.headline)
                                    Text(feature.description)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        acknowledgement
                    }
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                acknowledgement
                    .frame(maxWidth: 480)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var acknowledgement: some View {
        VStack(spacing: 12) {
            Text("Your journal is stored on this device by default.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                isShowingWelcome = false
            } label: {
                Text("I Agree")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func toggleEye() {
        isEyeOpen.toggle()
        playHapticFeedback()
    }

    let features = [
        Feature(
            title: "Risk & Reliability",
            description: "Any reliance you place on " + appName + " is strictly at your own risk. The developer is not liable.",
            image: "brain.head.profile"
        ),
        Feature(
            title: "Third Party Resources",
            description: "All data in the app should be verified with other sources for accuracy.",
            image: "person.2.wave.2"
        ),
        Feature(
            title: "Consult a Doctor",
            description: "Consult a doctor before making medical decisions.",
            image: "heart.text.square"
        ),
    ]
}

#Preview {
    WelcomeScreen(isShowingWelcome: .constant(true))
        .preferredColorScheme(.dark)
        .accentColor(Color.blue)
}
