import Foundation
import CoreMotion
import WebKit

final class MotionStepsBridge: NSObject, WKScriptMessageHandler {
    private let pedometer = CMPedometer()
    weak var webView: WKWebView?
    private let trustedHost = "wazen-personal.onrender.com"

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "healthkitBridge",
              message.frameInfo.isMainFrame,
              let url = message.frameInfo.request.url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == trustedHost,
              (url.port == nil || url.port == 443),
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "authorize", "syncToday", "syncMotionSteps":
            syncToday()
        case "availability":
            send([
                "kind": "availability",
                "available": false,
                "motionAvailable": CMPedometer.isStepCountingAvailable()
            ])
        case "diagnostics":
            send([
                "kind": "diagnostics",
                "bridgeVersion": "free-coremotion-v1",
                "healthAvailable": false,
                "motionStepAvailable": CMPedometer.isStepCountingAvailable(),
                "motionDistanceAvailable": CMPedometer.isDistanceAvailable(),
                "authorizationRequestStatus": "unavailable",
                "waterShareStatus": "unavailable",
                "osVersion": ProcessInfo.processInfo.operatingSystemVersionString
            ])
        case "saveWater":
            break
        default:
            break
        }
    }

    func syncToday() {
        guard CMPedometer.isStepCountingAvailable() else {
            send([
                "motionOnly": true,
                "motionAvailable": false,
                "connected": false,
                "source": "iPhone Motion",
                "error": "Step counting is not available on this iPhone."
            ])
            return
        }

        let start = Calendar.current.startOfDay(for: Date())
        pedometer.queryPedometerData(from: start, to: Date()) { [weak self] data, error in
            if let error {
                self?.send([
                    "motionOnly": true,
                    "motionAvailable": true,
                    "connected": false,
                    "source": "iPhone Motion",
                    "error": error.localizedDescription
                ])
                return
            }

            let steps = data?.numberOfSteps.intValue ?? 0
            let distanceKm = (data?.distance?.doubleValue ?? 0) / 1000
            self?.send([
                "motionOnly": true,
                "motionAvailable": true,
                "connected": true,
                "source": "iPhone Motion",
                "steps": steps,
                "distanceKm": (distanceKm * 100).rounded() / 100,
                "date": self?.todayString() ?? ""
            ])
        }
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func send(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(
                "window.WAZENHealthKit && window.WAZENHealthKit.receive(\(json));"
            )
        }
    }
}
