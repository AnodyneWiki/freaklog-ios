import SwiftUI

struct LockScreen: View {
    let isEyeOpen: Bool
    let isFaceIDEnabled: Bool
    var body: some View {
        VStack(spacing: 0) {
            Image(decorative: isEyeOpen ? "Eye Open" : "Eye Closed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 150, height: 150, alignment: .top)
            if !isFaceIDEnabled {
                Spacer().frame(height: 20)
                Text("Face ID is disabled.\nEnable it for Journal in settings to unlock the app.")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 25)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(Color(UIColor.systemBackground))
    }
}

#Preview {
    LockScreen(isEyeOpen: false, isFaceIDEnabled: false)
}
