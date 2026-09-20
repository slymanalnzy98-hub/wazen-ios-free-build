import SwiftUI
import WebKit
import UIKit

struct WazenWebView: UIViewRepresentable {
    private static let productionURL = URL(string: "https://wazen-personal.onrender.com/?source=ios-native")!
    fileprivate static let trustedHost = "wazen-personal.onrender.com"

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(context.coordinator.motionBridge, name: "healthkitBridge")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.backgroundColor = UIColor(red: 0.027, green: 0.063, blue: 0.102, alpha: 1)
        webView.isOpaque = false
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.motionBridge.webView = webView

        webView.load(URLRequest(
            url: Self.productionURL,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 30
        ))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "healthkitBridge")
        coordinator.motionBridge.webView = nil
    }

    fileprivate static func isTrustedURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == trustedHost else { return false }
        return url.port == nil || url.port == 443
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let motionBridge = MotionStepsBridge()

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func appDidBecomeActive() {
            motionBridge.syncToday()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "about" || WazenWebView.isTrustedURL(url) {
                decisionHandler(.allow)
                return
            }
            if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == true {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            motionBridge.webView = webView
            webView.evaluateJavaScript("document.documentElement.classList.add('ios-native');")
            motionBridge.syncToday()
        }
    }
}
