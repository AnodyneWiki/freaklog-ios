import SwiftUI

/// A header view that changes appearance based on its scroll position.
/// When pinned to the top of a `LazyVStack`, it adopts a material background and a divider.
/// Requires the parent ScrollView to have a `.coordinateSpace(name: "scroll")`.
struct ChameleonHeader: View {
    let title: String
    let date: Date
    var dynamicExperienceDestination: GlobalNavigationDestination? = nil
    var onPinnedStateChanged: ((Bool) -> Void)? = nil
    
    @State private var isPinnedInternal = false

    var body: some View {
        GeometryReader { geometry in
            let minY = geometry.frame(in: .named("scroll")).minY
            let isPinned = minY <= 1.0
            
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundColor(isPinnedInternal ? .primary : .secondary)
                        .textCase(.uppercase)
                    
                    Spacer()
                    
                    if let dynamicExperienceDestination = dynamicExperienceDestination {
                        NavigationLink(value: dynamicExperienceDestination) {
                            Label("Overview", systemImage: "arrow.down.left.and.arrow.up.right.square")
                                .labelStyle(.iconOnly)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
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
            .onAppear {
                isPinnedInternal = isPinned
                if isPinned {
                    onPinnedStateChanged?(true)
                }
            }
            .onChange(of: isPinned) { newValue in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isPinnedInternal = newValue
                }
                onPinnedStateChanged?(newValue)
            }
            .onDisappear {
                // If the header disappears (scrolled off screen or recycled), we should consider it unpinned/handled.
                onPinnedStateChanged?(false)
            }
        }
        .frame(height: 38)
    }
}
