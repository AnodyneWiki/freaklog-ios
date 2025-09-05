import MobileCoreServices
import SwiftUI

struct WebViewScreen: View {
    let articleURL: URL
    @State private var isWebViewLoading = true

    var body: some View {
        ZStack {
            VStack(alignment: .trailing, spacing: 0) {
                WebViewRepresentable(isLoading: $isWebViewLoading, url: articleURL)
            }
            .toolbar {
                ToolbarItemGroup {
                    ShareLink(item: articleURL)
                    Link(destination: articleURL) {
                        Label("Open in Safari", systemImage: "safari")
                    }
                }
            }
            if isWebViewLoading {
                ProgressView()
            }
        }
    }
}

#Preview {
    WebViewScreen(articleURL: URL(string: "https://psychonautwiki.org/wiki/LSD")!)
}
