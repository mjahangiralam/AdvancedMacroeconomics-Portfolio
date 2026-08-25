import SwiftUI
import WebKit

struct MobileWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 7/255, green: 17/255, blue: 31/255, alpha: 1)

        let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30)
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showError(in: webView, message: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showError(in: webView, message: error.localizedDescription)
        }

        private func showError(in webView: WKWebView, message: String) {
            let safe = message
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let html = """
            <!doctype html><meta name='viewport' content='width=device-width,initial-scale=1'>
            <style>body{margin:0;background:#07111f;color:#eef4fb;font-family:-apple-system;padding:32px}button{padding:12px 16px;border:0;border-radius:10px;background:#73e4ba;font-weight:700}</style>
            <h2>Waterloo Work</h2><p>Could not connect to the service.</p><p style='color:#91a5bd'>\(safe)</p>
            <button onclick='location.href="https://waterloo-work-mobile-ui-ai-econ-lab.vercel.app"'>Try again</button>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}
