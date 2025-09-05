import SwiftUI

struct OnFirstAppearModifier: ViewModifier {

    let perform: () -> Void

    @State private var isFirstAppear = true

    func body(content: Content) -> some View {
        content.onAppear {
            if isFirstAppear {
                perform()
                isFirstAppear = false
            }
        }
    }
}

extension View {
    func onFirstAppear(perform: @escaping () -> Void) -> some View {
        modifier(OnFirstAppearModifier(perform: perform))
    }
}
