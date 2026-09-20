import SwiftUI

@main
struct WazenApp: App {
    var body: some Scene {
        WindowGroup {
            WazenWebView()
                .preferredColorScheme(.dark)
        }
    }
}
