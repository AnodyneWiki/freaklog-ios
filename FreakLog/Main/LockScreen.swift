import SwiftUI

struct LockScreen: View {
    let isFaceIDEnabled: Bool
    var isAuthenticating = false
    var unlock: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    Image(decorative: "Eye Closed")
                        .resizable()
                        .scaledToFit()
                        .frame(width: symbolSize, height: symbolSize)
                    if let unlock {
                        Text("Journal Locked")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        if !isFaceIDEnabled {
                            Text("Set up device authentication in Settings to unlock FreakLog.")
                                .foregroundStyle(.secondary)
                        }
                        if isAuthenticating {
                            ProgressView("Unlocking…")
                        } else {
                            Button(isFaceIDEnabled ? "Unlock Journal" : "Try Again", action: unlock)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                        }
                    } else {
                        ProgressView("Opening Journal…")
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    private var symbolSize: CGFloat { dynamicTypeSize.isAccessibilitySize ? 64 : 100 }
}

#Preview {
    LockScreen(isFaceIDEnabled: false, unlock: {})
}
