import SwiftUI
import UIKit
import WebKit

struct WazenWebView: UIViewRepresentable {
    private static let productionURL = URL(string: "https://wazen-personal.onrender.com/?source=ios-native")!
    private static let healthURL = URL(string: "https://wazen-personal.onrender.com/healthz")!
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
        webView.scrollView.backgroundColor = UIColor(red: 0.012, green: 0.027, blue: 0.051, alpha: 1)
        webView.backgroundColor = UIColor(red: 0.012, green: 0.027, blue: 0.051, alpha: 1)
        webView.isOpaque = false
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.motionBridge.webView = webView

        Self.loadStartupScreen(in: webView)
        context.coordinator.startProductionWhenReady(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WKWebView, context: Context) -> CGSize? {
        let screen = UIScreen.main.bounds.size
        return CGSize(
            width: proposal.width ?? screen.width,
            height: proposal.height ?? screen.height
        )
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "healthkitBridge")
        coordinator.motionBridge.webView = nil
    }

    fileprivate static func isTrustedURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == trustedHost else { return false }
        return url.port == nil || url.port == 443
    }

    private static func loadProductionApp(in webView: WKWebView) {
        webView.load(URLRequest(
            url: Self.productionURL,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 30
        ))
    }

    private static func isReadyResponse(data: Data?, response: URLResponse?) -> Bool {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return false
        }

        return (json["ok"] as? Bool) == true
            && (json["service"] as? String) == "wazen-personal"
    }

    private static func loadStartupScreen(in webView: WKWebView) {
        let startup = """
        <!doctype html>
        <html lang="ar" dir="rtl">
        <head>
          <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
          <style>
            *{box-sizing:border-box}
            html,body{width:100%;height:100%;margin:0;background:#03070d;color:#f7fbff}
            body{display:grid;place-items:center;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Tahoma,Arial,sans-serif}
            .wrap{text-align:center;padding:32px}
            .mark{width:68px;height:68px;margin:0 auto 20px;border-radius:22px;display:grid;place-items:center;
              font-weight:900;font-size:28px;background:linear-gradient(135deg,#ff6b10,#ff9b42);
              box-shadow:0 16px 45px rgba(255,107,16,.22)}
            h1{margin:0;font-size:31px;letter-spacing:.08em}
            p{margin:10px 0 0;color:#91a2b8;font-size:14px}
            .spinner{width:28px;height:28px;margin:26px auto 0;border:3px solid #263547;border-top-color:#ff7617;
              border-radius:50%;animation:spin .85s linear infinite}
            @keyframes spin{to{transform:rotate(360deg)}}
          </style>
        </head>
        <body>
          <div class="wrap">
            <div class="mark">W</div>
            <h1>WAZEN</h1>
            <p>جاري تشغيل وازن…</p>
            <div class="spinner" aria-label="جاري التحميل"></div>
          </div>
        </body>
        </html>
        """
        webView.loadHTMLString(startup, baseURL: nil)
    }

    private static func loadFallback(in webView: WKWebView, error: Error) {
        let message = error.localizedDescription
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let fallback = """
        <!doctype html>
        <html lang="ar" dir="rtl">
        <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <body style="margin:0;min-height:100vh;display:grid;place-items:center;background:#03070d;color:white;font-family:-apple-system;padding:32px;text-align:center">
          <div>
            <h2>WAZEN</h2>
            <p>تعذر فتح WAZEN.</p>
            <p style="color:#91a2b8">تحقق من اتصال الإنترنت ثم أعد فتح التطبيق.</p>
            <p style="color:#5f7388;font-size:12px">\(message)</p>
          </div>
        </body>
        </html>
        """
        webView.loadHTMLString(fallback, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let motionBridge = MotionStepsBridge()

        private var readinessTask: URLSessionDataTask?
        private var readinessAttempt = 0
        private var isLoadingProduction = false
        private var productionDidFinish = false
        private var showedFallback = false
        private var stopped = false
        private let maxReadinessAttempts = 20

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
            guard productionDidFinish else { return }
            motionBridge.syncToday()
        }

        func startProductionWhenReady(in webView: WKWebView) {
            probeReadiness(for: webView)
        }

        func stop() {
            stopped = true
            readinessTask?.cancel()
            readinessTask = nil
        }

        private func probeReadiness(for webView: WKWebView) {
            guard !stopped, !isLoadingProduction else { return }

            readinessAttempt += 1
            var request = URLRequest(
                url: WazenWebView.healthURL,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: 8
            )
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            readinessTask = URLSession.shared.dataTask(with: request) { [weak self, weak webView] data, response, _ in
                guard let self, let webView, !self.stopped else { return }

                if WazenWebView.isReadyResponse(data: data, response: response) {
                    DispatchQueue.main.async {
                        guard !self.stopped, !self.isLoadingProduction else { return }
                        self.isLoadingProduction = true
                        WazenWebView.loadProductionApp(in: webView)
                    }
                    return
                }

                guard self.readinessAttempt < self.maxReadinessAttempts else {
                    DispatchQueue.main.async {
                        guard !self.showedFallback else { return }
                        self.showedFallback = true
                        let error = NSError(
                            domain: "WAZEN",
                            code: 1001,
                            userInfo: [NSLocalizedDescriptionKey: "تعذر تشغيل خدمة WAZEN خلال المهلة المحددة."]
                        )
                        WazenWebView.loadFallback(in: webView, error: error)
                    }
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.probeReadiness(for: webView)
                }
            }
            readinessTask?.resume()
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

            guard let url = webView.url, WazenWebView.isTrustedURL(url) else { return }
            productionDidFinish = true
            webView.evaluateJavaScript("document.documentElement.classList.add('ios-native');")
            motionBridge.syncToday()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard isLoadingProduction, !showedFallback else { return }
            showedFallback = true
            WazenWebView.loadFallback(in: webView, error: error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard isLoadingProduction, !showedFallback else { return }
            showedFallback = true
            WazenWebView.loadFallback(in: webView, error: error)
        }
    }
}
