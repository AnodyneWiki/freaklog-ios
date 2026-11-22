import SwiftUI
import WebKit

// MARK: - WebViewRepresentable

struct WebViewRepresentable: UIViewRepresentable {
    @Binding var isLoading: Bool
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateUIView(_: WKWebView, context _: Context) { }

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(isLoading: $isLoading)
    }
}

// MARK: - WebViewCoordinator

class WebViewCoordinator: NSObject, WKNavigationDelegate {
    init(isLoading: Binding<Bool>) {
        _isLoading = isLoading
    }

    @Binding var isLoading: Bool

    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        isLoading = true
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        isLoading = false
    }

    // Without these the spinner stayed on pages that failed to load
    func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        isLoading = false
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
        isLoading = false
    }
}
