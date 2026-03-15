import SwiftUI
import WebKit

/// Wraps a WKWebView to render React-based pages that don't yet have native SwiftUI views.
///
/// In DEBUG builds, loads from the Vite dev server at localhost:5173.
/// In RELEASE builds, loads from the bundled `dist/` directory.
struct WebFallbackView: NSViewRepresentable {
    let path: String
    var authToken: String? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        loadPage(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Reload if the path changed
        let currentPath = webView.url?.path ?? ""
        if currentPath != path {
            loadPage(in: webView)
        }
    }

    private func loadPage(in webView: WKWebView) {
        let baseURL: String
        #if DEBUG
        baseURL = "http://localhost:5173"
        #else
        if let distURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist") {
            webView.loadFileURL(distURL, allowingReadAccessTo: distURL.deletingLastPathComponent())
            return
        }
        baseURL = "http://localhost:5173"
        #endif

        var urlString = baseURL + path
        if let token = authToken {
            urlString += (urlString.contains("?") ? "&" : "?") + "token=\(token)"
        }

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }
}
