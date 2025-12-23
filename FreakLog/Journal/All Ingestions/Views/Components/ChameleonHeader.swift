import SwiftUI

/// A header view that changes appearance based on its scroll position.
/// When pinned to the top of a `LazyVStack`, it adopts a material background and a divider.
/// Requires the parent ScrollView to have a `.coordinateSpace(name: "scroll")`.
struct ChameleonHeader: View {
    let title: String
    let date: Date
    
    @State private var isPinnedInternal = false

    var body: some View {
        GeometryReader { geometry in
            let minY = geometry.frame(in: .named("scroll")).minY
            let isPinned = minY <= 0.5
            
            VStack(spacing: 0) {
                // Buffer space that compresses
                // We use a frame instead of a conditional Spacer for smoother layout transitions
                Color.clear
                    .frame(height: isPinnedInternal ? 0 : 24)
                
                HStack {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundColor(isPinnedInternal ? .primary : .secondary)
                        .textCase(.uppercase)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background {
                    // Material background for the text area only when pinned
                    Rectangle()
                        .fill(.regularMaterial)
                        .opacity(isPinnedInternal ? 1 : 0)
                }
                .overlay(alignment: .bottom) {
                    Divider()
                        .opacity(isPinnedInternal ? 1 : 0)
                }
            }
            .onAppear {
                isPinnedInternal = isPinned
            }
            .onChange(of: isPinned) { newValue in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isPinnedInternal = newValue
                }
            }
        }
        .frame(height: 56)
    }
}
